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
const {
  PLAN_CONFIGURATION,
  buildBillingContext,
  buildPlanCatalog,
  billingManager,
  entitlementIsActiveAt,
  exactKeys,
  getPremiumBillingContextWithoutStripe,
  parseBillingContextRequest,
  readAccountState,
} = require("./billing_context");

const REGION = "europe-west1";
const BILLING_RETURN_URL = "https://yovoice.app/premium";
const CHECKOUT_SUCCESS_URL =
  "https://yovoice.app/premium?checkout=success&session_id={CHECKOUT_SESSION_ID}";
const CHECKOUT_CANCEL_URL = "https://yovoice.app/premium?checkout=cancelled";
const STRIPE_CHECKOUT_HOST = "checkout.stripe.com";
const STRIPE_BILLING_PORTAL_HOST = "billing.stripe.com";
// The Stripe webhook is public by design. Reject work that cannot possibly be
// authentic before invoking the Stripe SDK so an anonymous oversized request
// cannot buy unbounded HMAC CPU, instances or warning logs.
const MAX_STRIPE_WEBHOOK_BODY_BYTES = 128 * 1024;
const MAX_STRIPE_WEBHOOK_INSTANCES = 10;
const INVALID_WEBHOOK_WARNING_INTERVAL_MS = 60 * 1000;

const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");
const STRIPE_WEBHOOK_SECRET = defineSecret("STRIPE_WEBHOOK_SECRET");
const STRIPE_MONTHLY_PRICE_ID = defineString("STRIPE_MONTHLY_PRICE_ID");
const STRIPE_YEARLY_PRICE_ID = defineString("STRIPE_YEARLY_PRICE_ID");
const STRIPE_BLIK_MONTHLY_PRICE_ID = defineString(
  "STRIPE_BLIK_MONTHLY_PRICE_ID",
);
const STRIPE_BLIK_YEARLY_PRICE_ID = defineString(
  "STRIPE_BLIK_YEARLY_PRICE_ID",
);
const STRIPE_PORTAL_CONFIGURATION_ID = defineString(
  "STRIPE_PORTAL_CONFIGURATION_ID",
  { default: "" },
);
const STRIPE_EXPECTED_MODE = defineString("STRIPE_EXPECTED_MODE");

function rawWebhookBodyByteLength(rawBody) {
  if (Buffer.isBuffer(rawBody)) return rawBody.byteLength;
  if (typeof rawBody === "string") return Buffer.byteLength(rawBody, "utf8");
  return null;
}

function stripeSignatureHeader(request) {
  const value = typeof request?.get === "function"
    ? request.get("stripe-signature")
    : request?.headers?.["stripe-signature"];
  return typeof value === "string" && value.length > 0 && value.length <= 8192
    ? value
    : null;
}

const BLIK_PLAN_CONFIGURATION = Object.freeze({
  monthly: Object.freeze({ currency: "pln", unitAmount: 2600, durationDays: 30 }),
  yearly: Object.freeze({ currency: "pln", unitAmount: 26000, durationDays: 365 }),
});
const ACTIVE_SUBSCRIPTION_STATUSES = new Set(["active", "trialing"]);
const GRACE_SUBSCRIPTION_STATUSES = new Set(["past_due"]);
const TERMINAL_SUBSCRIPTION_STATUSES = new Set(["canceled", "incomplete_expired"]);

function isAllowedStripeHostedUrl(value, expectedHost) {
  if (typeof value !== "string" || value.length > 4096) return false;
  try {
    const parsed = new URL(value);
    return (
      parsed.protocol === "https:" &&
      parsed.hostname === expectedHost &&
      parsed.port === "" &&
      parsed.username === "" &&
      parsed.password === ""
    );
  } catch (_) {
    return false;
  }
}

function parseCheckoutRequest(data) {
  const input = data ?? {};
  if (
    !exactKeys(input, ["plan", "paymentMethod"]) ||
    !Object.hasOwn(input, "plan") ||
    (input.paymentMethod !== undefined &&
      !Object.hasOwn(input, "paymentMethod")) ||
    !Object.hasOwn(PLAN_CONFIGURATION, input.plan)
  ) {
    throw new HttpsError(
      "invalid-argument",
      "plan must be monthly or yearly.",
    );
  }
  const paymentMethod = input.paymentMethod ?? "recurring";
  if (!["recurring", "blik"].includes(paymentMethod)) {
    throw new HttpsError(
      "invalid-argument",
      "paymentMethod must be recurring or blik.",
    );
  }
  return { plan: input.plan, paymentMethod };
}

function parsePortalRequest(data) {
  const input = data ?? {};
  if (!exactKeys(input, []) || Object.keys(input).length !== 0) {
    throw new HttpsError("invalid-argument", "This request takes no fields.");
  }
}

function validateConfiguredPrice(price, plan, expectedLiveMode) {
  const configuration = PLAN_CONFIGURATION[plan];
  if (
    !price ||
    price.object !== "price" ||
    price.active !== true ||
    price.type !== "recurring" ||
    price.billing_scheme !== "per_unit" ||
    price.transform_quantity != null ||
    price.recurring?.interval !== configuration.interval ||
    price.recurring?.interval_count !== 1 ||
    price.recurring?.usage_type !== "licensed" ||
    price.recurring?.aggregate_usage != null ||
    price.livemode !== expectedLiveMode
  ) {
    throw new Error(`Stripe ${plan} Price is not an active one-${configuration.interval} recurring Price.`);
  }
  if (
    price.currency !== configuration.currency ||
    price.unit_amount !== configuration.unitAmount ||
    price.tax_behavior !== "inclusive"
  ) {
    throw new Error(
      `Stripe ${plan} Price must be ${configuration.currency.toUpperCase()} ${configuration.unitAmount} with inclusive tax.`,
    );
  }
  if (Object.keys(price.currency_options ?? {}).length > 0) {
    throw new Error(
      `Stripe ${plan} Price has manual currency options; YO Voice uses Adaptive Pricing instead.`,
    );
  }
}

function validateConfiguredBlikPrice(price, plan, expectedLiveMode) {
  const configuration = BLIK_PLAN_CONFIGURATION[plan];
  if (
    !configuration ||
    !price ||
    price.object !== "price" ||
    price.active !== true ||
    price.type !== "one_time" ||
    price.billing_scheme !== "per_unit" ||
    price.transform_quantity != null ||
    price.recurring != null ||
    price.livemode !== expectedLiveMode ||
    price.currency !== configuration.currency ||
    price.unit_amount !== configuration.unitAmount ||
    price.tax_behavior !== "inclusive"
  ) {
    throw new Error(
      `Stripe ${plan} BLIK Price must be a one-time PLN ${configuration?.unitAmount} Price with inclusive tax.`,
    );
  }
  if (Object.keys(price.currency_options ?? {}).length > 0) {
    throw new Error(
      `Stripe ${plan} BLIK Price must not define manual currency options.`,
    );
  }
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
    if (!TERMINAL_SUBSCRIPTION_STATUSES.has(subscription.status)) {
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

async function expireOpenCheckoutSessionsForCustomer(
  stripe,
  customerId,
  pendingSessionId,
) {
  const expiredSessionIds = new Set();
  let startingAfter;
  do {
    const page = await stripe.checkout.sessions.list({
      customer: customerId,
      status: "open",
      limit: 100,
      ...(startingAfter ? { starting_after: startingAfter } : {}),
    });
    if (!Array.isArray(page.data)) {
      throw new Error("Stripe Checkout Session pagination returned invalid data.");
    }
    for (const session of page.data) {
      const sessionCustomerId = stripeObjectId(session.customer, "cus_");
      if (
        typeof session.id !== "string" ||
        !session.id.startsWith("cs_") ||
        sessionCustomerId !== customerId
      ) {
        throw new Error(
          "Stripe returned a Checkout Session for another customer.",
        );
      }
      if (session.status !== "open") continue;
      await stripe.checkout.sessions.expire(
        session.id,
        {},
        {
          idempotencyKey: `yovoice_expire_auth_delete_${customerId}_${session.id}`,
        },
      );
      expiredSessionIds.add(session.id);
    }
    startingAfter = page.has_more
      ? page.data[page.data.length - 1]?.id
      : undefined;
    if (page.has_more && !startingAfter) {
      throw new Error("Stripe Checkout Session pagination made no progress.");
    }
  } while (startingAfter);

  // The list endpoint can be eventually consistent immediately after Session
  // creation. The stored id is an additional canonical fallback, not the only
  // Session considered during account deletion.
  if (
    typeof pendingSessionId === "string" &&
    pendingSessionId.startsWith("cs_") &&
    !expiredSessionIds.has(pendingSessionId)
  ) {
    const pending = await stripe.checkout.sessions.retrieve(pendingSessionId);
    const pendingCustomerId = stripeObjectId(pending.customer, "cus_");
    if (pending.id !== pendingSessionId || pendingCustomerId !== customerId) {
      throw new Error(
        "Stored Checkout Session does not match its canonical customer.",
      );
    }
    if (pending.status === "open") {
      await stripe.checkout.sessions.expire(
        pendingSessionId,
        {},
        {
          idempotencyKey: `yovoice_expire_auth_delete_${customerId}_${pendingSessionId}`,
        },
      );
      expiredSessionIds.add(pendingSessionId);
    }
  }
  return expiredSessionIds.size;
}

function stripeObjectId(value, prefix) {
  const id = typeof value === "string" ? value : value?.id;
  return typeof id === "string" && id.startsWith(prefix) ? id : null;
}

function billingAccountIsDeleted(billing) {
  return (
    billing?.accountDeletionTombstone === true ||
    Number.isFinite(billing?.accountDeletedAt?.toMillis?.())
  );
}

function userProfileIsDeleted(snapshot) {
  if (!snapshot.exists) return true;
  const user = snapshot.data() ?? {};
  return (
    user.deleted === true ||
    user.status === "deleted" ||
    Number.isFinite(user.authDeletedAt?.toMillis?.())
  );
}

async function cancelCanonicalStripeSubscription(
  stripe,
  subscriptionId,
  customerId,
  idempotencyScope,
) {
  const subscription = await stripe.subscriptions.retrieve(subscriptionId);
  if (
    subscription.id !== subscriptionId ||
    stripeObjectId(subscription.customer, "cus_") !== customerId
  ) {
    throw new Error("Stripe subscription does not match its canonical customer.");
  }
  if (TERMINAL_SUBSCRIPTION_STATUSES.has(subscription.status)) {
    return { canceled: false, alreadyTerminal: true };
  }
  await stripe.subscriptions.cancel(
    subscriptionId,
    {},
    {
      idempotencyKey: `yovoice_cancel_${idempotencyScope}_${subscriptionId}`,
    },
  );
  return { canceled: true, alreadyTerminal: false };
}

function invoiceSubscriptionId(invoice) {
  if (invoice?.parent?.type !== "subscription_details") return null;
  return stripeObjectId(
    invoice?.parent?.subscription_details?.subscription,
    "sub_",
  );
}

function invoicePaymentIntentId(invoicePayment) {
  if (invoicePayment?.payment?.type !== "payment_intent") return null;
  return stripeObjectId(invoicePayment.payment.payment_intent, "pi_");
}

async function cancelStripeBillingForDeletedUser(
  uid,
  { firestore, stripe, now = () => Timestamp.now() },
) {
  const billingRef = firestore.collection("billingAccounts").doc(uid);
  const entitlementRef = firestore.collection("entitlements").doc(uid);
  const deletionTime = now();
  let billing = {};
  await firestore.runTransaction(async (transaction) => {
    const [snapshot, entitlementSnapshot] = await Promise.all([
      transaction.get(billingRef),
      transaction.get(entitlementRef),
    ]);
    billing = snapshot.data() ?? {};
    transaction.set(
      billingRef,
      {
        accountDeletionTombstone: true,
        accountDeletedAt: billing.accountDeletedAt ?? deletionTime,
        accountDeletionCancellationStatus: "pending",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    if (entitlementSnapshot.exists) {
      const prior = entitlementSnapshot.data() ?? {};
      const expiredEntitlement = buildEntitlements({
        plan: ["monthly", "yearly"].includes(prior.plan) ? prior.plan : "none",
        status: "expired",
        currentPeriodEnd: deletionTime,
        source: prior.source ?? "unknown",
      });
      applyEntitlementsInTransaction(transaction, uid, expiredEntitlement, {
        firestore,
        writeUserProjection: false,
      });
    }
  });
  const customerId = billing.stripeCustomerId;
  if (
    typeof customerId !== "string" ||
    !customerId.startsWith("cus_")
  ) {
    await billingRef.set(
      {
        accountDeletionCancellationStatus: "no-stripe-subscription",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return { outcome: "no-stripe-subscription" };
  }

  await expireOpenCheckoutSessionsForCustomer(
    stripe,
    customerId,
    billing.pendingCheckoutSessionId,
  );

  const canceledCount = await cancelStripeSubscriptionsForCustomer(
    stripe,
    customerId,
    `auth_delete_${uid}`,
  );
  await billingRef.set(
    {
      accountDeletionTombstone: true,
      accountDeletedAt: billing.accountDeletedAt ?? deletionTime,
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
  if (
    !plan ||
    subscription.items?.data?.length !== 1 ||
    subscription.items.data[0]?.quantity !== 1
  ) {
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
  const [profileSnapshot, billingSnapshot] = await Promise.all([
    firestore.collection("users").doc(request.auth.uid).get(),
    firestore.collection("billingAccounts").doc(request.auth.uid).get(),
  ]);
  const profile = profileSnapshot.data() ?? {};
  if (
    !profileSnapshot.exists ||
    profile.banned === true ||
    profile.disabled === true ||
    profile.deleted === true ||
    profile.status === "deleted" ||
    Number.isFinite(profile.authDeletedAt?.toMillis?.()) ||
    billingAccountIsDeleted(billingSnapshot.data() ?? {})
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
  let lastInvalidWebhookWarningAtMs = Number.NEGATIVE_INFINITY;

  async function loadPrices() {
    const nowMs = now().toMillis();
    if (priceCache && priceCache.expiresAtMs > nowMs) return priceCache.value;
    if (priceCache?.promise) return priceCache.promise;
    const promise = Promise.all([
      stripe.prices.retrieve(priceIds.monthly, { expand: ["currency_options"] }),
      stripe.prices.retrieve(priceIds.yearly, { expand: ["currency_options"] }),
      stripe.prices.retrieve(priceIds.blikMonthly, {
        expand: ["currency_options"],
      }),
      stripe.prices.retrieve(priceIds.blikYearly, {
        expand: ["currency_options"],
      }),
    ]).then(([monthly, yearly, blikMonthly, blikYearly]) => {
      validateConfiguredPrice(monthly, "monthly", expectedLiveMode);
      validateConfiguredPrice(yearly, "yearly", expectedLiveMode);
      validateConfiguredBlikPrice(blikMonthly, "monthly", expectedLiveMode);
      validateConfiguredBlikPrice(blikYearly, "yearly", expectedLiveMode);
      const monthlyProduct =
        typeof monthly.product === "string" ? monthly.product : monthly.product?.id;
      const yearlyProduct =
        typeof yearly.product === "string" ? yearly.product : yearly.product?.id;
      const blikMonthlyProduct =
        typeof blikMonthly.product === "string"
          ? blikMonthly.product
          : blikMonthly.product?.id;
      const blikYearlyProduct =
        typeof blikYearly.product === "string"
          ? blikYearly.product
          : blikYearly.product?.id;
      if (
        !monthlyProduct ||
        monthlyProduct !== yearlyProduct ||
        monthlyProduct !== blikMonthlyProduct ||
        monthlyProduct !== blikYearlyProduct
      ) {
        throw new Error("All Stripe Premium Prices must belong to the same Product.");
      }
      const value = { monthly, yearly, blikMonthly, blikYearly };
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
    // Portal configuration is mutable under the same bpc_ id. Validate it on
    // every session creation so a Dashboard change cannot retain a five-minute
    // window for quantity/promotion-code or unapproved Price updates.
    const [prices, configuration] = await Promise.all([
      loadPrices(),
      stripe.billingPortal.configurations.retrieve(portalConfigurationId, {
        expand: ["features.subscription_update.products"],
      }),
    ]);
    const cancelEnabled =
      configuration.active === true &&
      configuration.features?.subscription_cancel?.enabled === true &&
      configuration.features?.subscription_cancel?.mode === "at_period_end";
    const update = configuration.features?.subscription_update;
    const priceUpdateEnabled =
      update?.enabled === true &&
      Array.isArray(update.default_allowed_updates) &&
      update.default_allowed_updates.length === 1 &&
      update.default_allowed_updates[0] === "price";
    const expectedProduct =
      typeof prices.monthly.product === "string"
        ? prices.monthly.product
        : prices.monthly.product?.id;
    const products = Array.isArray(update?.products) ? update.products : [];
    const matchingProduct = products.length === 1 ? products[0] : null;
    const matchingProductId =
      typeof matchingProduct?.product === "string"
        ? matchingProduct.product
        : matchingProduct?.product?.id;
    const quantityAdjustmentDisabled =
      matchingProduct?.adjustable_quantity?.enabled === false;
    const allowedPriceIds = (matchingProduct?.prices ?? []).map((entry) =>
      typeof entry === "string" ? entry : entry?.id,
    );
    const expectedPriceIds = [prices.monthly.id, prices.yearly.id].sort();
    if (
      !cancelEnabled ||
      !priceUpdateEnabled ||
      matchingProductId !== expectedProduct ||
      !quantityAdjustmentDisabled ||
      allowedPriceIds.length !== 2 ||
      !allowedPriceIds.every((id) => typeof id === "string") ||
      JSON.stringify([...allowedPriceIds].sort()) !==
        JSON.stringify(expectedPriceIds)
    ) {
      throw new Error(
        "Stripe Portal must allow cancellation and switching between both configured Premium Prices.",
      );
    }
    return configuration;
  }

  async function accountState(uid) {
    return readAccountState(firestore, uid);
  }

  function entitlementIsActive(entitlements) {
    return entitlementIsActiveAt(entitlements, now().toMillis());
  }

  async function withActiveCheckoutAccount(uid, callback = () => undefined) {
    const userRef = firestore.collection("users").doc(uid);
    const billingRef = firestore.collection("billingAccounts").doc(uid);
    return firestore.runTransaction(async (transaction) => {
      const [userSnapshot, billingSnapshot] = await Promise.all([
        transaction.get(userRef),
        transaction.get(billingRef),
      ]);
      const user = userSnapshot.data() ?? {};
      const billing = billingSnapshot.data() ?? {};
      if (
        userProfileIsDeleted(userSnapshot) ||
        user.banned === true ||
        user.disabled === true ||
        billingAccountIsDeleted(billing)
      ) {
        throw new HttpsError(
          "permission-denied",
          "This account cannot manage Premium.",
        );
      }
      return callback({ transaction, billingRef, billing });
    });
  }

  async function expireOpenCheckoutSession(sessionId) {
    if (typeof sessionId !== "string" || !sessionId.startsWith("cs_")) return;
    const session = await stripe.checkout.sessions.retrieve(sessionId);
    if (session.status === "open") {
      await stripe.checkout.sessions.expire(sessionId);
    }
  }

  async function clearCheckoutAttempt(uid, attemptToken) {
    await withActiveCheckoutAccount(
      uid,
      ({ transaction, billingRef, billing }) => {
        if (billing.pendingCheckoutAttemptToken !== attemptToken) return;
        transaction.set(
          billingRef,
          {
            pendingCheckoutAttemptToken: null,
            pendingCheckoutSessionId: null,
            pendingCheckoutPlan: null,
            pendingCheckoutPaymentMethod: null,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      },
    );
  }

  async function disposeUnboundStripeCustomer(uid, customerId) {
    if (typeof customerId !== "string" || !customerId.startsWith("cus_")) {
      throw new Error("Stripe returned an invalid Customer for cleanup.");
    }
    let cleanupStatus = "pending";
    try {
      const deleted = await stripe.customers.del(
        customerId,
        {},
        { idempotencyKey: `yovoice_delete_orphan_customer_${customerId}` },
      );
      if (deleted.id !== customerId || deleted.deleted !== true) {
        throw new Error("Stripe did not confirm Customer deletion.");
      }
      cleanupStatus = "deleted";
    } catch (deleteError) {
      try {
        const scrubbed = await stripe.customers.update(customerId, {
          metadata: { firebaseUid: "" },
        });
        if (scrubbed.id !== customerId) {
          throw new Error("Stripe returned a different Customer during scrub.");
        }
        cleanupStatus = "scrubbed";
      } catch (scrubError) {
        cleanupStatus = "pending";
      }
    }
    await firestore.collection("stripeCustomerCleanup").doc(customerId).set(
      {
        uid,
        stripeCustomerId: customerId,
        status: cleanupStatus,
        requiresManualCleanup: cleanupStatus === "pending",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return cleanupStatus;
  }

  async function getPremiumBillingContextHandler(request) {
    return getPremiumBillingContextWithoutStripe(
      request,
      firestore,
      now().toMillis(),
      { checkoutEnabled: true },
    );
  }

  async function createPremiumCheckoutSessionHandler(request) {
    const { plan, paymentMethod } = parseCheckoutRequest(request.data);
    const user = await requireActiveBillingUser(request, firestore);
    await consumeBillingRateLimit(firestore, user.uid, "checkout", { now: now() });
    const prices = await loadPrices();
    const lease = await acquireCheckoutLease(firestore, user.uid, { now: now() });
    try {
      const state = await accountState(user.uid);
      if (billingAccountIsDeleted(state.billing)) {
        throw new HttpsError(
          "permission-denied",
          "This account cannot manage Premium.",
        );
      }
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
        const customerIdempotencyKey = `yovoice_customer_${user.uid}_v1`;
        const customerCreateAttemptRef = firestore
          .collection("stripeCustomerCleanup")
          .doc(`create_${user.uid}`);
        // This record is written before crossing the provider boundary. If the
        // process loses Stripe's response, support (or a retry) can replay the
        // exact idempotent create and identify the otherwise-orphaned Customer.
        await withActiveCheckoutAccount(
          user.uid,
          ({ transaction }) =>
            transaction.set(
              customerCreateAttemptRef,
              {
                uid: user.uid,
                createIdempotencyKey: customerIdempotencyKey,
                status: "creating",
                requiresManualCleanup: true,
                updatedAt: FieldValue.serverTimestamp(),
              },
              { merge: true },
            ),
        );
        const customer = await stripe.customers.create(
          { metadata: { firebaseUid: user.uid } },
          { idempotencyKey: customerIdempotencyKey },
        );
        if (typeof customer.id !== "string" || !customer.id.startsWith("cus_")) {
          throw new Error("Stripe Customer creation returned an invalid id.");
        }
        await customerCreateAttemptRef.set(
          {
            stripeCustomerId: customer.id,
            status: "created-unbound",
            requiresManualCleanup: true,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        try {
          customerId = await withActiveCheckoutAccount(
            user.uid,
            ({ transaction, billingRef, billing }) => {
              const existingCustomerId = billing.stripeCustomerId;
              if (
                typeof existingCustomerId === "string" &&
                existingCustomerId.startsWith("cus_")
              ) {
                return existingCustomerId;
              }
              transaction.set(
                billingRef,
                {
                  stripeCustomerId: customer.id,
                  provider: "stripe",
                  updatedAt: FieldValue.serverTimestamp(),
                },
                { merge: true },
              );
              return customer.id;
            },
          );
        } catch (error) {
          const cleanupStatus = await disposeUnboundStripeCustomer(
            user.uid,
            customer.id,
          );
          await customerCreateAttemptRef.set(
            {
              status: cleanupStatus,
              requiresManualCleanup: cleanupStatus === "pending",
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
          throw error;
        }
        if (customerId !== customer.id) {
          const cleanupStatus = await disposeUnboundStripeCustomer(
            user.uid,
            customer.id,
          );
          await customerCreateAttemptRef.set(
            {
              status: cleanupStatus,
              requiresManualCleanup: cleanupStatus === "pending",
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        } else {
          await customerCreateAttemptRef.set(
            {
              status: "bound",
              requiresManualCleanup: false,
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        }
      }

      // Check every page before reusing a stored Checkout URL. A stale open
      // session is not proof that no subscription was activated elsewhere.
      const subscriptions = await listStripeSubscriptionsForCustomer(
        stripe,
        customerId,
      );
      const existing = subscriptions.find(
        (subscription) =>
          !TERMINAL_SUBSCRIPTION_STATUSES.has(subscription.status),
      );
      if (existing) {
        throw new HttpsError(
          "failed-precondition",
          "A Stripe subscription already exists. Manage it instead.",
          { reason: "stripe-subscription-exists", billingManagedBy: "stripe" },
        );
      }

      const pendingSessionId = state.billing.pendingCheckoutSessionId;
      const pendingPaymentMethod =
        state.billing.pendingCheckoutPaymentMethod ?? "recurring";
      if (
        typeof pendingSessionId === "string" &&
        pendingSessionId.startsWith("cs_")
      ) {
        const pending = await stripe.checkout.sessions.retrieve(pendingSessionId);
        if (
          state.billing.pendingCheckoutPlan === plan &&
          pendingPaymentMethod === paymentMethod &&
          pending.status === "open" &&
          isAllowedStripeHostedUrl(pending.url, STRIPE_CHECKOUT_HOST)
        ) {
          await withActiveCheckoutAccount(user.uid);
          return { url: pending.url };
        }
        if (pending.status === "open") {
          await stripe.checkout.sessions.expire(pendingSessionId);
        }
      }

      const savedAttemptToken = state.billing.pendingCheckoutAttemptToken;
      const attemptToken =
        !pendingSessionId &&
        state.billing.pendingCheckoutPlan === plan &&
        pendingPaymentMethod === paymentMethod &&
        typeof savedAttemptToken === "string" &&
        /^[0-9a-f-]{36}$/.test(savedAttemptToken)
          ? savedAttemptToken
          : lease.token;
      await withActiveCheckoutAccount(
        user.uid,
        ({ transaction, billingRef }) =>
          transaction.set(
            billingRef,
            {
              pendingCheckoutAttemptToken: attemptToken,
              // Clear a stale provider id before the external create. If this
              // invocation crashes after Stripe succeeds, the retry reuses the
              // persisted attempt token and therefore Stripe's idempotency key.
              pendingCheckoutSessionId: null,
              pendingCheckoutPlan: plan,
              pendingCheckoutPaymentMethod: paymentMethod,
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          ),
      );

      const isBlik = paymentMethod === "blik";
      const selectedPrice = isBlik
        ? prices[plan === "monthly" ? "blikMonthly" : "blikYearly"]
        : prices[plan];
      const session = await stripe.checkout.sessions.create(
        {
          mode: isBlik ? "payment" : "subscription",
          customer: customerId,
          payment_method_types: isBlik ? ["blik"] : ["card", "paypal"],
          client_reference_id: user.uid,
          line_items: [{ price: selectedPrice.id, quantity: 1 }],
          ...(!isBlik ? { adaptive_pricing: { enabled: true } } : {}),
          automatic_tax: { enabled: true },
          billing_address_collection: "required",
          customer_update: { address: "auto", name: "auto" },
          success_url: CHECKOUT_SUCCESS_URL,
          cancel_url: CHECKOUT_CANCEL_URL,
          metadata: { firebaseUid: user.uid, plan, paymentMethod },
          ...(!isBlik
            ? {
                subscription_data: {
                  metadata: { firebaseUid: user.uid, plan },
                },
              }
            : {}),
        },
        { idempotencyKey: `yovoice_checkout_${user.uid}_${attemptToken}` },
      );
      if (
        typeof session.id !== "string" ||
        !session.id.startsWith("cs_") ||
        session.status !== "open" ||
        !isAllowedStripeHostedUrl(session.url, STRIPE_CHECKOUT_HOST)
      ) {
        await clearCheckoutAttempt(user.uid, attemptToken);
        throw new Error("Stripe Checkout did not return an open hosted Session.");
      }
      try {
        await withActiveCheckoutAccount(
          user.uid,
          ({ transaction, billingRef }) =>
            transaction.set(
              billingRef,
              {
                pendingCheckoutSessionId: session.id,
                pendingCheckoutPlan: plan,
                pendingCheckoutPaymentMethod: paymentMethod,
                updatedAt: FieldValue.serverTimestamp(),
              },
              { merge: true },
            ),
        );
      } catch (error) {
        await expireOpenCheckoutSession(session.id);
        try {
          // This Session was deliberately expired, so its idempotency key must
          // not be reused on the next request (Stripe would return the same
          // unusable Session forever).
          await clearCheckoutAttempt(user.uid, attemptToken);
        } catch (cleanupError) {
          logger.warn("Stripe checkout attempt cleanup failed", {
            uid: user.uid,
            errorName: cleanupError?.name ?? null,
            errorCode: cleanupError?.code ?? null,
          });
        }
        throw error;
      }
      return { url: session.url };
    } finally {
      try {
        await releaseCheckoutLease(firestore, lease);
      } catch (error) {
        // The lease expires automatically. Never hide a valid Checkout URL
        // (or the original Stripe error) behind cleanup-only Firestore noise.
        logger.warn("Stripe checkout lease cleanup failed", {
          uid: user.uid,
          errorName: error?.name ?? null,
          errorCode: error?.code ?? null,
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
    const subscriptionId = state.billing.stripeSubscriptionId;
    if (
      state.entitlements.source !== "stripe" ||
      typeof subscriptionId !== "string" ||
      !subscriptionId.startsWith("sub_")
    ) {
      throw new HttpsError(
        "failed-precondition",
        manager === "stripe"
          ? "This Stripe purchase is prepaid and has no subscription portal."
          : "This subscription is managed by another provider.",
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
    const subscription = await stripe.subscriptions.retrieve(subscriptionId);
    const subscriptionCustomerId =
      typeof subscription.customer === "string"
        ? subscription.customer
        : subscription.customer?.id;
    if (
      subscription.id !== subscriptionId ||
      subscriptionCustomerId !== customerId
    ) {
      throw new HttpsError(
        "failed-precondition",
        "The Stripe subscription does not belong to this billing account.",
        { reason: "stripe-subscription-owner-mismatch" },
      );
    }
    await loadPortalConfiguration();
    const session = await stripe.billingPortal.sessions.create({
      customer: customerId,
      return_url: BILLING_RETURN_URL,
      configuration: portalConfigurationId,
    });
    if (!isAllowedStripeHostedUrl(session.url, STRIPE_BILLING_PORTAL_HOST)) {
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

  async function readCanonicalPrepaidCheckout(sessionId) {
    if (typeof sessionId !== "string" || !sessionId.startsWith("cs_")) {
      throw new Error("Stripe prepaid event is missing a valid Checkout Session id.");
    }
    const prices = await loadPrices();
    const session = await stripe.checkout.sessions.retrieve(sessionId, {
      expand: ["payment_intent"],
    });
    if (
      session.id !== sessionId ||
      session.mode !== "payment" ||
      session.status !== "complete" ||
      session.payment_status !== "paid"
    ) {
      throw new Error("Stripe prepaid Checkout is not complete and paid.");
    }

    const lineItems = await stripe.checkout.sessions.listLineItems(sessionId, {
      limit: 10,
      expand: ["data.price"],
    });
    if (!Array.isArray(lineItems.data) || lineItems.data.length !== 1) {
      throw new Error("Stripe prepaid Checkout must contain exactly one line item.");
    }
    const lineItem = lineItems.data[0];
    const priceId =
      typeof lineItem.price === "string" ? lineItem.price : lineItem.price?.id;
    const plan =
      priceId === prices.blikMonthly.id
        ? "monthly"
        : priceId === prices.blikYearly.id
          ? "yearly"
          : null;
    if (!plan || lineItem.quantity !== 1) {
      throw new Error("Stripe prepaid Checkout does not contain one configured BLIK Price.");
    }
    const configuration = BLIK_PLAN_CONFIGURATION[plan];
    if (
      session.currency !== configuration.currency ||
      session.amount_total !== configuration.unitAmount
    ) {
      throw new Error("Stripe prepaid Checkout total does not match its configured BLIK Price.");
    }

    const customerId =
      typeof session.customer === "string"
        ? session.customer
        : session.customer?.id;
    if (typeof customerId !== "string" || !customerId.startsWith("cus_")) {
      throw new Error("Stripe prepaid Checkout is missing its canonical Customer.");
    }
    const paymentIntentId =
      typeof session.payment_intent === "string"
        ? session.payment_intent
        : session.payment_intent?.id;
    if (
      typeof paymentIntentId !== "string" ||
      !paymentIntentId.startsWith("pi_")
    ) {
      throw new Error("Stripe prepaid Checkout is missing its PaymentIntent.");
    }
    const paymentIntent =
      typeof session.payment_intent === "object" && session.payment_intent
        ? session.payment_intent
        : await stripe.paymentIntents.retrieve(paymentIntentId);
    const paymentCustomerId =
      typeof paymentIntent.customer === "string"
        ? paymentIntent.customer
        : paymentIntent.customer?.id;
    const paymentMethodId = stripeObjectId(
      paymentIntent.payment_method,
      "pm_",
    );
    if (!paymentMethodId) {
      throw new Error("Stripe prepaid PaymentIntent is missing its PaymentMethod.");
    }
    const paymentMethod =
      typeof paymentIntent.payment_method === "object" &&
      paymentIntent.payment_method
        ? paymentIntent.payment_method
        : await stripe.paymentMethods.retrieve(paymentMethodId);
    if (
      paymentIntent.id !== paymentIntentId ||
      paymentIntent.status !== "succeeded" ||
      paymentIntent.currency !== configuration.currency ||
      paymentIntent.amount_received !== configuration.unitAmount ||
      paymentCustomerId !== customerId ||
      paymentMethod.id !== paymentMethodId ||
      paymentMethod.type !== "blik"
    ) {
      throw new Error("Stripe prepaid PaymentIntent is not a settled configured BLIK payment.");
    }
    return {
      session,
      customerId,
      paymentIntentId,
      plan,
      configuration,
    };
  }

  async function applyPrepaidPurchase(sessionId, event) {
    if (typeof event?.id !== "string" || !event.id.startsWith("evt_")) {
      throw new Error("Stripe prepaid event is missing a valid event id.");
    }
    const canonical = await readCanonicalPrepaidCheckout(sessionId);
    const { uid, billingRef } = await canonicalBillingBinding(
      canonical.customerId,
    );
    const eventRef = firestore.collection("stripeWebhookEvents").doc(event.id);
    // One receipt per Checkout Session prevents completed + async-succeeded
    // deliveries (or different event ids for the same payment) granting twice.
    const purchaseRef = firestore
      .collection("stripeWebhookEvents")
      .doc(`prepaid_${canonical.session.id}`);
    const financialRiskRef = firestore
      .collection("stripeFinancialRisks")
      .doc(canonical.paymentIntentId);
    let alreadyProcessed = false;
    let reviewRequired = false;
    let ignoredAfterDeletion = false;

    await firestore.runTransaction(async (transaction) => {
      alreadyProcessed = false;
      reviewRequired = false;
      ignoredAfterDeletion = false;
      const userRef = firestore.collection("users").doc(uid);
      const entitlementRef = firestore.collection("entitlements").doc(uid);
      const [
        eventSnapshot,
        purchaseSnapshot,
        billingSnapshot,
        userSnapshot,
        entitlementSnapshot,
        financialRiskSnapshot,
      ] = await Promise.all([
        transaction.get(eventRef),
        transaction.get(purchaseRef),
        transaction.get(billingRef),
        transaction.get(userRef),
        transaction.get(entitlementRef),
        transaction.get(financialRiskRef),
      ]);
      if (eventSnapshot.exists) {
        alreadyProcessed = true;
        return;
      }
      if (purchaseSnapshot.exists) {
        alreadyProcessed = true;
        transaction.create(eventRef, {
          type: event.type,
          created: event.created,
          duplicatePrepaidPurchase: true,
          processedAt: FieldValue.serverTimestamp(),
        });
        return;
      }
      const billing = billingSnapshot.data() ?? {};
      if (!billingSnapshot.exists || billing.stripeCustomerId !== canonical.customerId) {
        throw new Error("Stripe prepaid Customer does not match the canonical billing account.");
      }

      const previousEntitlement = entitlementSnapshot.data() ?? {};
      const activeEntitlement = entitlementIsActiveAt(
        previousEntitlement,
        now().toMillis(),
      );
      const receipt = {
        recordType: "prepaid-purchase",
        type: event.type,
        created: event.created,
        uid,
        plan: canonical.plan,
        checkoutSessionId: canonical.session.id,
        paymentIntentId: canonical.paymentIntentId,
        processedAt: FieldValue.serverTimestamp(),
      };
      const pendingCheckoutClear =
        billing.pendingCheckoutSessionId === canonical.session.id
          ? {
              pendingCheckoutSessionId: null,
              pendingCheckoutPlan: null,
              pendingCheckoutPaymentMethod: null,
            }
          : {};

      if (billingAccountIsDeleted(billing) || userProfileIsDeleted(userSnapshot)) {
        ignoredAfterDeletion = true;
        reviewRequired = true;
        transaction.set(
          billingRef,
          {
            billingReviewRequired: true,
            billingReviewReason: "prepaid-after-account-deletion",
            billingReviewEventId: event.id,
            ...pendingCheckoutClear,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        transaction.create(purchaseRef, {
          ...receipt,
          fulfillmentStatus: "account-deleted",
        });
        transaction.create(eventRef, {
          ...receipt,
          ignoredAfterAccountDeletion: true,
          supportReviewRequired: true,
        });
        return;
      }

      if (financialRiskSnapshot.exists) {
        reviewRequired = true;
        transaction.set(
          billingRef,
          {
            billingReviewRequired: true,
            billingReviewReason: "prepaid-payment-at-financial-risk",
            billingReviewEventId: event.id,
            ...pendingCheckoutClear,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        transaction.create(purchaseRef, {
          ...receipt,
          fulfillmentStatus: "financial-risk",
        });
        transaction.create(eventRef, {
          ...receipt,
          blockedByFinancialRisk: true,
          supportReviewRequired: true,
        });
        return;
      }

      // Checkout refuses active access before creating a Session. A different
      // entitlement can still land while the customer is paying. Never replace
      // a live subscription or silently stack time; retain the paid receipt and
      // send the overlap to support reconciliation.
      if (activeEntitlement) {
        reviewRequired = true;
        transaction.set(
          billingRef,
          {
            billingReviewRequired: true,
            billingReviewReason: "prepaid-active-entitlement-overlap",
            billingReviewEventId: event.id,
            ...pendingCheckoutClear,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        transaction.create(purchaseRef, {
          ...receipt,
          fulfillmentStatus: "manual-review",
        });
        transaction.create(eventRef, {
          ...receipt,
          supportReviewRequired: true,
        });
        return;
      }

      const currentPeriodEnd = Timestamp.fromMillis(
        now().toMillis() + canonical.configuration.durationDays * 86400000,
      );
      const entitlementData = buildEntitlements({
        plan: canonical.plan,
        status: "active",
        currentPeriodEnd,
        source: "stripe_prepaid",
      });
      transaction.set(
        billingRef,
        {
          provider: "stripe",
          prepaidAccessStatus: "active",
          currentPrepaidCheckoutSessionId: canonical.session.id,
          currentPrepaidPaymentIntentId: canonical.paymentIntentId,
          lastPrepaidCheckoutSessionId: canonical.session.id,
          lastPrepaidPaymentIntentId: canonical.paymentIntentId,
          currentPeriodEnd,
          renewalBehavior: "none",
          ...pendingCheckoutClear,
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
      transaction.create(purchaseRef, {
        ...receipt,
        fulfillmentStatus: "applied",
        currentPeriodEnd,
      });
      transaction.create(eventRef, {
        ...receipt,
        entitlementApplied: true,
      });
    });

    if (alreadyProcessed) return { ignored: true };
    if (ignoredAfterDeletion) return { ignored: true };
    if (reviewRequired) return { reviewRequired: true, uid };
    return { applied: true, uid, plan: canonical.plan };
  }

  async function readPaidSubscriptionInvoiceIdentity(
    subscription,
    customerId,
  ) {
    const invoice = subscription.latest_invoice;
    const invoiceId = stripeObjectId(invoice, "in_");
    if (
      !invoiceId ||
      !invoice ||
      typeof invoice !== "object" ||
      stripeObjectId(invoice.customer, "cus_") !== customerId ||
      invoiceSubscriptionId(invoice) !== subscription.id
    ) {
      throw new Error(
        "Paid Stripe subscription is missing its canonical latest Invoice.",
      );
    }
    const invoicePayments = await stripe.invoicePayments.list({
      invoice: invoiceId,
      status: "paid",
      limit: 2,
    });
    if (
      invoicePayments.has_more === true ||
      !Array.isArray(invoicePayments.data) ||
      invoicePayments.data.length !== 1
    ) {
      throw new Error(
        "Paid Stripe subscription must have one canonical Invoice Payment.",
      );
    }
    const invoicePayment = invoicePayments.data[0];
    const paymentIntentId = invoicePaymentIntentId(invoicePayment);
    if (
      invoicePayment.status !== "paid" ||
      stripeObjectId(invoicePayment.invoice, "in_") !== invoiceId ||
      !paymentIntentId
    ) {
      throw new Error("Stripe Invoice Payment does not match the subscription Invoice.");
    }
    const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
    if (
      paymentIntent.id !== paymentIntentId ||
      stripeObjectId(paymentIntent.customer, "cus_") !== customerId
    ) {
      throw new Error("Stripe Invoice Payment has the wrong customer.");
    }
    return { invoiceId, paymentIntentId };
  }

  async function chargeForFinancialEvent(event) {
    const eventObject = event.data.object;
    const chargeId =
      event.type === "charge.refunded"
        ? stripeObjectId(eventObject, "ch_")
        : stripeObjectId(eventObject.charge, "ch_");
    if (typeof chargeId !== "string" || !chargeId.startsWith("ch_")) {
      throw new Error("Stripe financial event is missing its charge.");
    }
    const charge = await stripe.charges.retrieve(chargeId);
    if (charge.id !== chargeId) {
      throw new Error("Stripe returned a different financial event charge.");
    }
    return charge;
  }

  async function readCanonicalFinancialCharge(charge) {
    const paymentIntentId = stripeObjectId(charge.payment_intent, "pi_");
    const customerId = stripeObjectId(charge.customer, "cus_");
    if (!paymentIntentId || !customerId) {
      throw new Error("Stripe charge is missing its PaymentIntent or Customer.");
    }
    const [paymentIntent, invoicePayments] = await Promise.all([
      stripe.paymentIntents.retrieve(paymentIntentId),
      stripe.invoicePayments.list({
        payment: { type: "payment_intent", payment_intent: paymentIntentId },
        status: "paid",
        limit: 2,
      }),
    ]);
    if (
      paymentIntent.id !== paymentIntentId ||
      stripeObjectId(paymentIntent.customer, "cus_") !== customerId
    ) {
      throw new Error("Stripe charge does not match its canonical PaymentIntent.");
    }
    if (!Array.isArray(invoicePayments.data)) {
      throw new Error("Stripe Invoice Payment lookup returned invalid data.");
    }
    if (invoicePayments.data.length === 0 && invoicePayments.has_more !== true) {
      return { customerId, paymentIntentId, recurringCharge: null };
    }
    if (invoicePayments.has_more === true || invoicePayments.data.length !== 1) {
      throw new Error("Stripe PaymentIntent has ambiguous Invoice ownership.");
    }
    const invoicePayment = invoicePayments.data[0];
    const invoiceId = stripeObjectId(invoicePayment.invoice, "in_");
    if (
      invoicePayment.status !== "paid" ||
      invoicePaymentIntentId(invoicePayment) !== paymentIntentId ||
      !invoiceId
    ) {
      throw new Error("Stripe Invoice Payment does not match its PaymentIntent.");
    }
    const invoice = await stripe.invoices.retrieve(invoiceId);
    const subscriptionId = invoiceSubscriptionId(invoice);
    if (
      invoice.id !== invoiceId ||
      stripeObjectId(invoice.customer, "cus_") !== customerId ||
      !subscriptionId
    ) {
      throw new Error("Stripe Invoice does not match its canonical subscription.");
    }
    const subscription = await stripe.subscriptions.retrieve(subscriptionId);
    if (
      subscription.id !== subscriptionId ||
      stripeObjectId(subscription.customer, "cus_") !== customerId
    ) {
      throw new Error(
        "Stripe recurring charge does not match its canonical Subscription.",
      );
    }
    return {
      customerId,
      paymentIntentId,
      recurringCharge: { customerId, invoiceId, paymentIntentId, subscriptionId },
    };
  }

  async function applyFinancialRiskEvent(event) {
    if (typeof event?.id !== "string" || !event.id.startsWith("evt_")) {
      throw new Error("Stripe financial event is missing a valid event id.");
    }
    const charge = await chargeForFinancialEvent(event);
    const customerId = stripeObjectId(charge.customer, "cus_");
    const { uid, billingRef } = await canonicalBillingBinding(customerId);
    const eventRef = firestore.collection("stripeWebhookEvents").doc(event.id);
    // Stripe can replay an old refund after a later purchase. Deduplicate
    // before any cancellation side effect, not merely before Firestore writes.
    const initialEventSnapshot = await eventRef.get();
    if (
      initialEventSnapshot.exists &&
      initialEventSnapshot.data()?.processingState !==
        "financial-cancel-pending"
    ) {
      return { ignored: true };
    }

    if (
      event.type === "charge.refunded" &&
      (!Number.isSafeInteger(charge.amount) ||
        !Number.isSafeInteger(charge.amount_refunded) ||
        charge.amount_refunded < 0 ||
        charge.amount_refunded > charge.amount)
    ) {
      throw new Error("Stripe refund amounts are invalid.");
    }
    const isPartialRefund =
      event.type === "charge.refunded" &&
      charge.amount_refunded < charge.amount;
    const canonicalFinancial = await readCanonicalFinancialCharge(charge);
    const recurringCharge = canonicalFinancial.recurringCharge;
    if (canonicalFinancial.customerId !== customerId) {
      throw new Error("Stripe financial customer changed.");
    }

    if (isPartialRefund) {
      await firestore.runTransaction(async (transaction) => {
        const [eventSnapshot, billingSnapshot] = await Promise.all([
          transaction.get(eventRef),
          transaction.get(billingRef),
        ]);
        if (eventSnapshot.exists) return;
        if (billingSnapshot.data()?.stripeCustomerId !== customerId) {
          throw new Error("Financial event customer binding changed.");
        }
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
          subscriptionId: recurringCharge?.subscriptionId ?? null,
          paymentIntentId:
            recurringCharge?.paymentIntentId ??
            stripeObjectId(charge.payment_intent, "pi_"),
          supportReviewRequired: true,
          processedAt: FieldValue.serverTimestamp(),
        });
      });
      return { reviewRequired: true };
    }

    const riskPaymentIntentId =
      recurringCharge?.paymentIntentId ??
      canonicalFinancial.paymentIntentId;
    if (!riskPaymentIntentId) {
      throw new Error("Stripe financial event is missing its PaymentIntent.");
    }
    const financialRiskRef = firestore
      .collection("stripeFinancialRisks")
      .doc(riskPaymentIntentId);
    const financialRiskData = {
      paymentIntentId: riskPaymentIntentId,
      invoiceId: recurringCharge?.invoiceId ?? null,
      subscriptionId: recurringCharge?.subscriptionId ?? null,
      customerId,
      latestEventId: event.id,
      latestEventType: event.type,
      accessBlocked: true,
      updatedAt: FieldValue.serverTimestamp(),
    };

    // A one-time BLIK payment has no Invoice. Its refund/dispute must never
    // cancel a separate subscription that the customer bought later. Recheck
    // ownership and the actually-applied purchase receipt in one transaction.
    if (!recurringCharge) {
      const paymentIntentId = stripeObjectId(charge.payment_intent, "pi_");
      let alreadyProcessed = false;
      let currentPrepaidRevoked = false;
      await firestore.runTransaction(async (transaction) => {
        alreadyProcessed = false;
        currentPrepaidRevoked = false;
        const userRef = firestore.collection("users").doc(uid);
        const entitlementRef = firestore.collection("entitlements").doc(uid);
        const [eventSnapshot, billingSnapshot, userSnapshot, entitlementSnapshot] =
          await Promise.all([
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
          throw new Error("Financial event customer binding changed.");
        }
        const prior = entitlementSnapshot.data() ?? {};
        // Only the explicit current receipt is revocation authority. The
        // legacy `lastPrepaid*` fields are audit history and may refer to an
        // older or unfulfilled payment.
        const currentPaymentIntentId = billing.currentPrepaidPaymentIntentId;
        const currentCheckoutSessionId = billing.currentPrepaidCheckoutSessionId;
        const purchaseRef =
          typeof currentCheckoutSessionId === "string" &&
          currentCheckoutSessionId.startsWith("cs_")
            ? firestore
                .collection("stripeWebhookEvents")
                .doc(`prepaid_${currentCheckoutSessionId}`)
            : null;
        const purchaseSnapshot = purchaseRef
          ? await transaction.get(purchaseRef)
          : null;
        const purchase = purchaseSnapshot?.data() ?? {};
        transaction.set(financialRiskRef, financialRiskData, { merge: true });
        const isCurrentPrepaid =
          paymentIntentId &&
          currentPaymentIntentId === paymentIntentId &&
          billing.prepaidAccessStatus === "active" &&
          prior.source === "stripe_prepaid" &&
          !billingAccountIsDeleted(billing) &&
          !userProfileIsDeleted(userSnapshot) &&
          purchaseSnapshot?.exists === true &&
          purchase.fulfillmentStatus === "applied" &&
          purchase.paymentIntentId === paymentIntentId &&
          purchase.checkoutSessionId === currentCheckoutSessionId;

        if (!isCurrentPrepaid) {
          transaction.set(
            billingRef,
            {
              billingReviewRequired: true,
              billingReviewReason: "non-current-prepaid-financial-event",
              billingReviewEventId: event.id,
              lastFinancialEventId: event.id,
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
          transaction.create(eventRef, {
            type: event.type,
            created: event.created,
            paymentIntentId:
              typeof paymentIntentId === "string" ? paymentIntentId : null,
            ignoredAsNonCurrentPrepaid: true,
            supportReviewRequired: true,
            processedAt: FieldValue.serverTimestamp(),
          });
          return;
        }

        currentPrepaidRevoked = true;
        const entitlementData = buildEntitlements({
          plan: ["monthly", "yearly"].includes(prior.plan)
            ? prior.plan
            : "none",
          status: "expired",
          currentPeriodEnd: now(),
          source: "stripe_prepaid",
        });
        transaction.set(
          billingRef,
          {
            prepaidAccessStatus: "revoked",
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
          paymentIntentId,
          currentPrepaidAccessRevoked: true,
          accessRevoked: true,
          processedAt: FieldValue.serverTimestamp(),
        });
      });
      if (alreadyProcessed) return { ignored: true };
      if (currentPrepaidRevoked) return { revoked: true };
      return { reviewRequired: true };
    }

    let alreadyProcessed = false;
    let nonCurrentRecurring = false;
    let financialOperationOwned = false;
    let financialOperationInProgress = false;
    const financialOperationToken = randomUUID();
    const financialOperationLeaseUntil = Timestamp.fromMillis(
      now().toMillis() + 60_000,
    );
    await firestore.runTransaction(async (transaction) => {
      alreadyProcessed = false;
      nonCurrentRecurring = false;
      financialOperationOwned = false;
      financialOperationInProgress = false;
      const userRef = firestore.collection("users").doc(uid);
      const entitlementRef = firestore.collection("entitlements").doc(uid);
      const [eventSnapshot, billingSnapshot, userSnapshot, entitlementSnapshot] =
        await Promise.all([
          transaction.get(eventRef),
          transaction.get(billingRef),
          transaction.get(userRef),
          transaction.get(entitlementRef),
        ]);
      const billing = billingSnapshot.data() ?? {};
      const entitlement = entitlementSnapshot.data() ?? {};
      if (!billingSnapshot.exists || billing.stripeCustomerId !== customerId) {
        throw new Error("Financial event customer binding changed.");
      }
      if (eventSnapshot.exists) {
        const receipt = eventSnapshot.data() ?? {};
        const leaseUntilMs = receipt.operationLeaseUntil?.toMillis?.();
        if (
          receipt.processingState === "financial-cancel-pending" &&
          receipt.subscriptionId === recurringCharge.subscriptionId &&
          (!Number.isFinite(leaseUntilMs) || leaseUntilMs <= now().toMillis())
        ) {
          financialOperationOwned = true;
          transaction.set(
            eventRef,
            {
              operationToken: financialOperationToken,
              operationLeaseUntil: financialOperationLeaseUntil,
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        } else if (receipt.processingState === "financial-cancel-pending") {
          financialOperationInProgress = true;
        } else {
          alreadyProcessed = true;
        }
        return;
      }
      const isCurrentRecurring =
        billing.stripeSubscriptionId === recurringCharge.subscriptionId &&
        billing.currentInvoiceId === recurringCharge.invoiceId &&
        billing.currentPaymentIntentId === recurringCharge.paymentIntentId &&
        entitlement.source === "stripe" &&
        !billingAccountIsDeleted(billing) &&
        !userProfileIsDeleted(userSnapshot);
      transaction.set(financialRiskRef, financialRiskData, { merge: true });
      if (isCurrentRecurring) {
        financialOperationOwned = true;
        transaction.create(eventRef, {
          type: event.type,
          created: event.created,
          subscriptionId: recurringCharge.subscriptionId,
          invoiceId: recurringCharge.invoiceId,
          paymentIntentId: recurringCharge.paymentIntentId,
          processingState: "financial-cancel-pending",
          operationToken: financialOperationToken,
          operationLeaseUntil: financialOperationLeaseUntil,
          queuedAt: FieldValue.serverTimestamp(),
        });
        return;
      }

      nonCurrentRecurring = true;
      transaction.set(
        billingRef,
        {
          billingReviewRequired: true,
          billingReviewReason: "non-current-recurring-financial-event",
          billingReviewEventId: event.id,
          lastFinancialEventId: event.id,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      transaction.create(eventRef, {
        type: event.type,
        created: event.created,
        subscriptionId: recurringCharge.subscriptionId,
        invoiceId: recurringCharge.invoiceId,
        paymentIntentId: recurringCharge.paymentIntentId,
        ignoredAsNonCurrentRecurring: true,
        supportReviewRequired: true,
        processedAt: FieldValue.serverTimestamp(),
      });
    });
    if (alreadyProcessed) return { ignored: true };
    if (financialOperationInProgress) return { inProgress: true };
    if (nonCurrentRecurring) return { reviewRequired: true };
    if (!financialOperationOwned) {
      throw new Error("Stripe financial cancellation was not claimed.");
    }

    // Cancel only the exact subscription paid by this Invoice. Never sweep all
    // subscriptions on the Customer: a later purchase may already be current.
    await cancelCanonicalStripeSubscription(
      stripe,
      recurringCharge.subscriptionId,
      customerId,
      event.id,
    );

    let supersededBeforeRevocation = false;
    let financialOperationCompleted = false;
    await firestore.runTransaction(async (transaction) => {
      supersededBeforeRevocation = false;
      financialOperationCompleted = false;
      const userRef = firestore.collection("users").doc(uid);
      const entitlementRef = firestore.collection("entitlements").doc(uid);
      const [eventSnapshot, billingSnapshot, userSnapshot, entitlementSnapshot] =
        await Promise.all([
          transaction.get(eventRef),
          transaction.get(billingRef),
          transaction.get(userRef),
          transaction.get(entitlementRef),
        ]);
      const receipt = eventSnapshot.data() ?? {};
      if (
        !eventSnapshot.exists ||
        receipt.processingState !== "financial-cancel-pending" ||
        receipt.operationToken !== financialOperationToken
      ) {
        throw new Error("Stripe financial cancellation claim changed.");
      }
      const billing = billingSnapshot.data() ?? {};
      const prior = entitlementSnapshot.data() ?? {};
      if (billing.stripeCustomerId !== customerId) {
        throw new Error("Financial event customer binding changed.");
      }
      if (
        billing.stripeSubscriptionId !== recurringCharge.subscriptionId ||
        billing.currentInvoiceId !== recurringCharge.invoiceId ||
        billing.currentPaymentIntentId !== recurringCharge.paymentIntentId ||
        prior.source !== "stripe" ||
        billingAccountIsDeleted(billing) ||
        userProfileIsDeleted(userSnapshot)
      ) {
        supersededBeforeRevocation = true;
        transaction.set(
          billingRef,
          {
            billingReviewRequired: true,
            billingReviewReason: "recurring-financial-event-superseded",
            billingReviewEventId: event.id,
            lastFinancialEventId: event.id,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        transaction.set(eventRef, {
          type: event.type,
          created: event.created,
          subscriptionId: recurringCharge.subscriptionId,
          processingState: "completed",
          operationLeaseUntil: null,
          supersededBeforeRevocation: true,
          supportReviewRequired: true,
          processedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
        financialOperationCompleted = true;
        return;
      }
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
      transaction.set(eventRef, {
        type: event.type,
        created: event.created,
        subscriptionId: recurringCharge.subscriptionId,
        invoiceId: recurringCharge.invoiceId,
        paymentIntentId: recurringCharge.paymentIntentId,
        processingState: "completed",
        operationLeaseUntil: null,
        accessRevoked: true,
        processedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      financialOperationCompleted = true;
    });
    if (!financialOperationCompleted) {
      throw new Error("Stripe financial cancellation did not complete.");
    }
    if (supersededBeforeRevocation) return { reviewRequired: true };
    return { revoked: true };
  }

  async function applySubscription(subscriptionId, event) {
    if (typeof subscriptionId !== "string" || !subscriptionId.startsWith("sub_")) {
      throw new Error("Stripe webhook has no valid subscription id.");
    }
    if (typeof event?.id !== "string" || !event.id.startsWith("evt_")) {
      throw new Error("Stripe subscription event is missing a valid event id.");
    }
    // The webhook must enforce the same commercial configuration as Checkout;
    // matching an id alone is not pricing authority.
    await loadPrices();
    const initialSubscription = await stripe.subscriptions.retrieve(subscriptionId);
    if (initialSubscription.id !== subscriptionId) {
      throw new Error("Stripe returned a different subscription.");
    }
    const customerId = stripeObjectId(initialSubscription.customer, "cus_");
    if (typeof customerId !== "string" || !customerId.startsWith("cus_")) {
      throw new Error("Stripe subscription is missing its customer.");
    }
    const { uid, billingRef } = await canonicalBillingBinding(customerId);
    const eventRef = firestore.collection("stripeWebhookEvents").doc(event.id);
    let alreadyProcessed = false;
    let ignoredAsSuperseded = false;
    let overlap = null;
    await firestore.runTransaction(async (transaction) => {
      alreadyProcessed = false;
      ignoredAsSuperseded = false;
      overlap = null;
      // Refresh on every Firestore transaction retry. This closes the race in
      // which an older active event pauses here, a cancellation commits, and
      // the older handler resumes with a stale object and resurrects access.
      const subscription = await stripe.subscriptions.retrieve(subscriptionId, {
        expand: ["latest_invoice"],
      });
      const currentCustomerId = stripeObjectId(subscription.customer, "cus_");
      if (
        subscription.id !== subscriptionId ||
        currentCustomerId !== customerId
      ) {
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
      const billing = billingSnapshot.data() ?? {};
      if (!billingSnapshot.exists || billing.stripeCustomerId !== customerId) {
        throw new Error("Stripe customer does not match the canonical billing account.");
      }
      if (eventSnapshot.exists) {
        const receipt = eventSnapshot.data() ?? {};
        if (
          receipt.subscriptionId === subscriptionId &&
          ["cancel-pending", "review-pending"].includes(
            receipt.processingState,
          )
        ) {
          overlap = {
            reason: receipt.overlapReason,
            cancelRequired: receipt.cancelRequired === true,
            accountDeleted: receipt.ignoredAfterAccountDeletion === true,
            incomingWasTerminal: receipt.incomingWasTerminal === true,
          };
        } else {
          alreadyProcessed = true;
        }
        return;
      }
      const queueOverlap = ({
        reason,
        cancelRequired,
        accountDeleted = false,
        incomingWasTerminal = false,
      }) => {
        overlap = {
          reason,
          cancelRequired,
          accountDeleted,
          incomingWasTerminal,
        };
        transaction.create(eventRef, {
          type: event.type,
          created: event.created,
          subscriptionId,
          processingState: cancelRequired ? "cancel-pending" : "review-pending",
          overlapReason: reason,
          cancelRequired,
          incomingWasTerminal,
          entitlementOverlap: true,
          ignoredAfterAccountDeletion: accountDeleted,
          supportReviewRequired: true,
          queuedAt: FieldValue.serverTimestamp(),
        });
      };
      const incomingIsTerminal = TERMINAL_SUBSCRIPTION_STATUSES.has(
        subscription.status,
      );
      if (billingAccountIsDeleted(billing) || userProfileIsDeleted(userSnapshot)) {
        queueOverlap({
          reason: "subscription-after-account-deletion",
          cancelRequired: !incomingIsTerminal,
          accountDeleted: true,
          incomingWasTerminal: incomingIsTerminal,
        });
        return;
      }
      const mapped = mapStripeSubscription(subscription, priceIds, {
        previousEntitlement: entitlementSnapshot.data() ?? {},
        nowMs: now().toMillis(),
      });
      let settledIdentity = null;
      if (
        mapped.paymentSettled === true &&
        ["active", "trialing"].includes(mapped.status)
      ) {
        settledIdentity = await readPaidSubscriptionInvoiceIdentity(
          subscription,
          customerId,
        );
        const financialRiskSnapshot = await transaction.get(
          firestore
            .collection("stripeFinancialRisks")
            .doc(settledIdentity.paymentIntentId),
        );
        if (financialRiskSnapshot.exists) {
          queueOverlap({
            reason: "subscription-payment-at-financial-risk",
            cancelRequired: !incomingIsTerminal,
            incomingWasTerminal: incomingIsTerminal,
          });
          return;
        }
      }
      const priorEntitlement = entitlementSnapshot.data() ?? {};
      const priorSubscriptionId = billing.stripeSubscriptionId;
      let priorCanonicalIsTerminal = false;
      if (
        typeof priorSubscriptionId === "string" &&
        priorSubscriptionId !== subscriptionId
      ) {
        // Firestore is a projection, not subscription authority. Refresh the
        // stored canonical subscription before deciding that the incoming one
        // is a duplicate: an out-of-order webhook may leave a stale `active`
        // status after the old subscription has already ended at Stripe.
        const priorSubscription = await stripe.subscriptions.retrieve(
          priorSubscriptionId,
        );
        if (
          priorSubscription.id !== priorSubscriptionId ||
          stripeObjectId(priorSubscription.customer, "cus_") !== customerId
        ) {
          throw new Error(
            "Stored Stripe subscription does not match its canonical customer.",
          );
        }
        priorCanonicalIsTerminal = TERMINAL_SUBSCRIPTION_STATUSES.has(
          priorSubscription.status,
        );
        const incomingCanReplaceTerminalPrior =
          priorCanonicalIsTerminal &&
          !incomingIsTerminal &&
          ["active", "trialing"].includes(mapped.status);
        if (incomingCanReplaceTerminalPrior) {
          // Continue to the entitlement overlap guard below. It has an explicit
          // exception for replacing this now-terminal Stripe entitlement.
        } else if (incomingIsTerminal) {
          ignoredAsSuperseded = true;
          transaction.create(eventRef, {
            type: event.type,
            created: event.created,
            ignoredAsSuperseded: true,
            processedAt: FieldValue.serverTimestamp(),
          });
          return;
        } else {
          queueOverlap({
            reason: "duplicate-active-stripe-subscription",
            cancelRequired: true,
            incomingWasTerminal: false,
          });
          return;
        }
      }

      const priorIsActive = entitlementIsActiveAt(
        priorEntitlement,
        now().toMillis(),
      );
      const sameCanonicalStripeEntitlement =
        priorEntitlement.source === "stripe" &&
        billing.stripeSubscriptionId === subscriptionId;
      const replacesTerminalStripeEntitlement =
        priorCanonicalIsTerminal &&
        priorEntitlement.source === "stripe" &&
        ["active", "trialing"].includes(mapped.status);
      if (
        priorIsActive &&
        !sameCanonicalStripeEntitlement &&
        !replacesTerminalStripeEntitlement
      ) {
        queueOverlap({
          reason: "recurring-active-entitlement-overlap",
          cancelRequired: !incomingIsTerminal,
          incomingWasTerminal: incomingIsTerminal,
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
          ...(settledIdentity
            ? {
                currentInvoiceId: settledIdentity.invoiceId,
                currentPaymentIntentId: settledIdentity.paymentIntentId,
              }
            : {}),
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
    if (overlap) {
      const cancellation = overlap.cancelRequired
        ? await cancelCanonicalStripeSubscription(
            stripe,
            subscriptionId,
            customerId,
            `overlap_${event.id}`,
          )
        : {
            canceled: false,
            alreadyTerminal: overlap.incomingWasTerminal === true,
          };
      await firestore.runTransaction(async (transaction) => {
        const [eventSnapshot, billingSnapshot] = await Promise.all([
          transaction.get(eventRef),
          transaction.get(billingRef),
        ]);
        const receipt = eventSnapshot.data() ?? {};
        if (
          !eventSnapshot.exists ||
          receipt.subscriptionId !== subscriptionId ||
          !["cancel-pending", "review-pending"].includes(
            receipt.processingState,
          )
        ) {
          return;
        }
        if (billingSnapshot.data()?.stripeCustomerId !== customerId) {
          throw new Error("Stripe overlap customer binding changed.");
        }
        transaction.set(
          billingRef,
          {
            billingReviewRequired: true,
            billingReviewReason: overlap.reason,
            billingReviewEventId: event.id,
            duplicateStripeSubscriptionId: subscriptionId,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        transaction.set(eventRef, {
          type: event.type,
          created: event.created,
          subscriptionId,
          processingState: "completed",
          entitlementOverlap: true,
          cancellationRequested: overlap.cancelRequired,
          cancellationConverged:
            cancellation.canceled || cancellation.alreadyTerminal,
          incomingSubscriptionCanceled: cancellation.canceled,
          incomingSubscriptionAlreadyTerminal: cancellation.alreadyTerminal,
          ignoredAfterAccountDeletion: overlap.accountDeleted === true,
          supportReviewRequired: true,
          processedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
      });
      return overlap.accountDeleted
        ? { ignored: true }
        : { reviewRequired: true, uid };
    }
    return { applied: true, uid };
  }

  async function stripeWebhookHandler(request, response, webhookSecret) {
    if (request?.method !== "POST") {
      if (typeof response.set === "function") response.set("Allow", "POST");
      response.status(405).send("Method Not Allowed");
      return;
    }
    const bodyBytes = rawWebhookBodyByteLength(request?.rawBody);
    if (bodyBytes === null) {
      response.status(400).send("Invalid webhook");
      return;
    }
    if (bodyBytes > MAX_STRIPE_WEBHOOK_BODY_BYTES) {
      response.status(413).send("Payload Too Large");
      return;
    }
    const signature = stripeSignatureHeader(request);
    if (!signature) {
      response.status(400).send("Invalid signature");
      return;
    }
    let event;
    try {
      event = stripe.webhooks.constructEvent(
        request.rawBody,
        signature,
        webhookSecret,
      );
      if (event.livemode !== expectedLiveMode) {
        throw new Error("Stripe webhook mode does not match this deployment.");
      }
    } catch (error) {
      // Do not copy Stripe's externally-derived diagnostic string into logs;
      // some SDK errors include request/header context. The response stays
      // intentionally generic and operators still get a bounded class/code.
      const rejectedAtMs = now().toMillis();
      if (
        rejectedAtMs - lastInvalidWebhookWarningAtMs >=
        INVALID_WEBHOOK_WARNING_INTERVAL_MS
      ) {
        // Intentionally generic and sampled per warm instance. Stripe SDK
        // diagnostics can quote attacker-controlled header/body context.
        logger.warn("Stripe webhook signature rejected");
        lastInvalidWebhookWarningAtMs = rejectedAtMs;
      }
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
        if (session.mode === "payment") {
          await applyPrepaidPurchase(session.id, event);
        } else {
          subscriptionId =
            typeof session.subscription === "string"
              ? session.subscription
              : session.subscription?.id;
        }
      } else if (event.type === "checkout.session.async_payment_failed") {
        const session = event.data.object;
        subscriptionId =
          typeof session.subscription === "string"
            ? session.subscription
            : session.subscription?.id;
      } else if (["invoice.paid", "invoice.payment_failed"].includes(event.type)) {
        const invoice = event.data.object;
        subscriptionId = invoiceSubscriptionId(invoice);
      }
      if (subscriptionId) await applySubscription(subscriptionId, event);
      response.status(200).json({ received: true });
    } catch (error) {
      logger.error("Stripe webhook processing failed", {
        eventId: event.id,
        eventType: event.type,
        errorName: error?.name ?? null,
        errorCode: error?.code ?? null,
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
    applyPrepaidPurchase,
    readCanonicalPrepaidCheckout,
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
      blikMonthly: STRIPE_BLIK_MONTHLY_PRICE_ID.value(),
      blikYearly: STRIPE_BLIK_YEARLY_PRICE_ID.value(),
    },
    portalConfigurationId: STRIPE_PORTAL_CONFIGURATION_ID.value(),
    expectedLiveMode: expectedMode === "live",
  });
}

const billingCallableOptions = {
  region: REGION,
  secrets: [STRIPE_SECRET_KEY],
};

const createPremiumCheckoutSession = onCall(billingCallableOptions, (request) =>
  runtimeHandlers().createPremiumCheckoutSessionHandler(request),
);
const createPremiumPortalSession = onCall(billingCallableOptions, (request) =>
  runtimeHandlers().createPremiumPortalSessionHandler(request),
);
const stripePremiumWebhook = onRequest(
  {
    region: REGION,
    cors: false,
    secrets: [STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET],
    invoker: "public",
    maxInstances: MAX_STRIPE_WEBHOOK_INSTANCES,
    timeoutSeconds: 60,
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
  validateConfiguredBlikPrice,
  parseBillingContextRequest,
  parseCheckoutRequest,
  parsePortalRequest,
  billingManager,
  acquireCheckoutLease,
  releaseCheckoutLease,
  requireAuthenticatedBillingOwner,
  PLAN_CONFIGURATION,
  BLIK_PLAN_CONFIGURATION,
  isAllowedStripeHostedUrl,
  STRIPE_CHECKOUT_HOST,
  STRIPE_BILLING_PORTAL_HOST,
  MAX_STRIPE_WEBHOOK_BODY_BYTES,
  MAX_STRIPE_WEBHOOK_INSTANCES,
  rawWebhookBodyByteLength,
  stripeSignatureHeader,
};
