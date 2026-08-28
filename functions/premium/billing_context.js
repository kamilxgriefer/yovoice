const { Timestamp } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");

const { db } = require("../utils/firestore");

const REGION = "europe-west1";

// Public recurring catalog. Provider resource ids and payment details never
// leave the backend; clients receive only this exact display contract.
const PLAN_CONFIGURATION = Object.freeze({
  monthly: Object.freeze({
    interval: "month",
    currency: "eur",
    unitAmount: 600,
  }),
  yearly: Object.freeze({
    interval: "year",
    currency: "eur",
    unitAmount: 6000,
  }),
});

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

function formatMinorAmount(amount, currency, countryCode) {
  const divisor = ZERO_DECIMAL_CURRENCIES.has(currency) ? 1 : 100;
  const locale = countryCode ? `und-${countryCode}` : "en";
  return new Intl.NumberFormat(locale, {
    style: "currency",
    currency: currency.toUpperCase(),
  }).format(amount / divisor);
}

function buildPlanCatalog(countryCode) {
  const monthlyAmount = PLAN_CONFIGURATION.monthly.unitAmount;
  const plans = ["monthly", "yearly"].map((id) => {
    const configuration = PLAN_CONFIGURATION[id];
    const yearly = id === "yearly";
    const equivalentAmount = yearly
      ? Math.round(configuration.unitAmount / 12)
      : null;
    const savingsPercent = yearly
      ? Math.max(
          0,
          Math.round(
            (1 - configuration.unitAmount / (monthlyAmount * 12)) * 100,
          ),
        )
      : 0;
    return {
      id,
      interval: configuration.interval,
      currency: configuration.currency.toUpperCase(),
      unitAmount: configuration.unitAmount,
      formattedPrice: formatMinorAmount(
        configuration.unitAmount,
        configuration.currency,
        countryCode,
      ),
      formattedEquivalent: yearly
        ? formatMinorAmount(
            equivalentAmount,
            configuration.currency,
            countryCode,
          )
        : null,
      savingsPercent,
    };
  });

  return {
    countryCode,
    currency: "EUR",
    priceDisplaySource: "base",
    localizedAtCheckout: true,
    taxDisplay: "included",
    taxNotice:
      "The EUR base price includes applicable tax. Stripe shows the final currency and tax before payment.",
    plans,
  };
}

function billingManager(source) {
  if (source === "stripe" || source === "stripe_prepaid") return "stripe";
  if (["apple", "appStore", "ios"].includes(source)) return "apple";
  if (["google", "googlePlay", "play"].includes(source)) return "google";
  if (source === "admin") return "admin";
  return "none";
}

function entitlementIsActiveAt(entitlements, nowMs) {
  const periodEndMs = entitlements.currentPeriodEnd?.toMillis?.();
  return (
    entitlements.isPremium === true &&
    ["active", "trialing", "grace"].includes(entitlements.status) &&
    Number.isFinite(periodEndMs) &&
    periodEndMs > nowMs
  );
}

function hasCanonicalStripeSubscription(state) {
  return (
    state.entitlements.source === "stripe" &&
    typeof state.billing.stripeCustomerId === "string" &&
    state.billing.stripeCustomerId.startsWith("cus_") &&
    typeof state.billing.stripeSubscriptionId === "string" &&
    state.billing.stripeSubscriptionId.startsWith("sub_")
  );
}

function buildBillingContext(
  countryCode,
  state,
  nowMs,
  { checkoutEnabled = false } = {},
) {
  const manager = billingManager(state.entitlements.source);
  const active = entitlementIsActiveAt(state.entitlements, nowMs);
  const canonicalStripeSubscription = hasCanonicalStripeSubscription(state);
  return {
    ...buildPlanCatalog(countryCode),
    billingManagedBy: manager,
    // A terminal subscription id is deliberately retained for audit and
    // Provider Portal recovery, so its mere presence cannot suppress a new
    // purchase forever. The Checkout handler performs the authoritative,
    // paginated provider scan before creating any Session.
    checkoutAvailable: checkoutEnabled && !active,
    portalAvailable:
      checkoutEnabled && canonicalStripeSubscription,
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
  { checkoutEnabled = false } = {},
) {
  const { countryCode } = parseBillingContextRequest(request.data);
  const state = await readAccountState(firestore, request.auth?.uid);
  return buildBillingContext(countryCode, state, nowMs, { checkoutEnabled });
}

function stripeCheckoutIsExported() {
  return process.env.STRIPE_BILLING_EXPORTS === "enabled";
}

// This catalog/context endpoint intentionally declares no provider secret. It
// remains deployable while Checkout is disabled, so /premium can always render
// truthful prices. checkoutAvailable stays false until the operator explicitly
// enables the separately secret-bound Stripe endpoints.
const getPremiumBillingContext = onCall(
  { region: REGION, maxInstances: 20, concurrency: 80 },
  (request) =>
    getPremiumBillingContextWithoutStripe(
      request,
      db,
      Timestamp.now().toMillis(),
      { checkoutEnabled: stripeCheckoutIsExported() },
    ),
);

module.exports = {
  PLAN_CONFIGURATION,
  buildBillingContext,
  buildPlanCatalog,
  billingManager,
  entitlementIsActiveAt,
  exactKeys,
  getPremiumBillingContext,
  getPremiumBillingContextWithoutStripe,
  hasCanonicalStripeSubscription,
  parseBillingContextRequest,
  readAccountState,
  stripeCheckoutIsExported,
};
