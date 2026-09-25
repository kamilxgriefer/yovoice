// In-app bug reports: the export map.
//
// Eight exports are always registered and need no new secret:
//
//   submitBugReportV1, attachBugReportScreenshotV1   any signed-in account
//   listBugReportsV1, getBugReportV1,
//   updateBugReportStatusV1, deleteBugReportV1,
//   deleteBugReportScreenshotV1                      the protected owner only
//   sweepBugReportRetentionSchedule                  daily retention sweep
//
// `deliverBugReportV1` is registered ONLY when index.js source-enables a
// delivery channel, and only then are that channel's secrets declared — lazily,
// inside this function, so deploy discovery never collects them while the
// channel is off (the GIPHY_API_KEY pattern, ADR-214).
//
// Nothing here performs I/O or constructs a provider SDK at load: Firestore
// and the (lazy) Storage bucket are resolved on the first invocation.

const { onCall } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");

const REGION = "europe-west1";

const BUG_REPORT_BASE_EXPORT_NAMES = Object.freeze([
  "attachBugReportScreenshotV1",
  "deleteBugReportScreenshotV1",
  "deleteBugReportV1",
  "getBugReportV1",
  "listBugReportsV1",
  "submitBugReportV1",
  "sweepBugReportRetentionSchedule",
  "updateBugReportStatusV1",
]);
const BUG_REPORT_DELIVERY_EXPORT = "deliverBugReportV1";

function defaultRuntime() {
  const { getFirestore, Timestamp } = require("firebase-admin/firestore");
  const { getStorage } = require("firebase-admin/storage");
  const { createLazyBucket } = require("../utils/lazy_bucket");
  const { requireProtectedOwner } = require("../utils/auth");
  const { createBugReportService, createBugReportStorageAdapter } = require("./service");
  const logger = require("firebase-functions/logger");
  const db = getFirestore();
  return {
    db,
    Timestamp,
    logger,
    service: createBugReportService({
      db,
      Timestamp,
      logger,
      storage: createBugReportStorageAdapter(createLazyBucket(() => getStorage().bucket())),
      authorizeOwner: (request) => requireProtectedOwner(request),
    }),
  };
}

/**
 * @param {object} [options]
 * @param {boolean} [options.emailDelivery]   source gate: Resend e-mail alerts
 * @param {boolean} [options.githubDelivery]  source gate: GitHub issue alerts
 * @param {boolean} [options.enforceAppCheck]
 * @param {object}  [options.registrars]      injected by tests
 * @param {Function}[options.runtimeFactory]  injected by tests
 */
function createBugReportFunctions({
  emailDelivery = false,
  githubDelivery = false,
  enforceAppCheck = false,
  registrars = { onCall, onSchedule, onDocumentCreated },
  runtimeFactory = defaultRuntime,
} = {}) {
  let runtime = null;
  const resolve = () => (runtime ??= runtimeFactory());

  const reporterOptions = { region: REGION, enforceAppCheck, memory: "256MiB", timeoutSeconds: 60 };
  const ownerOptions = {
    region: REGION,
    enforceAppCheck,
    memory: "256MiB",
    timeoutSeconds: 60,
    // The owner gate reads it; nothing else in this module needs a secret.
    secrets: ["YOVOICE_PROTECTED_OWNER_UID"],
  };

  const exported = {
    submitBugReportV1: registrars.onCall(reporterOptions,
      (request) => resolve().service.submitBugReportV1(request)),
    attachBugReportScreenshotV1: registrars.onCall(reporterOptions,
      (request) => resolve().service.attachBugReportScreenshotV1(request)),
    listBugReportsV1: registrars.onCall(ownerOptions,
      (request) => resolve().service.listBugReportsV1(request)),
    getBugReportV1: registrars.onCall(ownerOptions,
      (request) => resolve().service.getBugReportV1(request)),
    updateBugReportStatusV1: registrars.onCall(ownerOptions,
      (request) => resolve().service.updateBugReportStatusV1(request)),
    // Rights requests (access and erasure): delete one report, or only its
    // screenshot, now rather than at the 180/90-day sweep. Both audited.
    deleteBugReportV1: registrars.onCall(ownerOptions,
      (request) => resolve().service.deleteBugReportV1(request)),
    deleteBugReportScreenshotV1: registrars.onCall(ownerOptions,
      (request) => resolve().service.deleteBugReportScreenshotV1(request)),
    sweepBugReportRetentionSchedule: registrars.onSchedule({
      region: REGION,
      schedule: "every 24 hours",
      timeZone: "UTC",
      maxInstances: 1,
      timeoutSeconds: 300,
      memory: "256MiB",
    }, async () => {
      await resolve().service.sweepBugReportRetention();
    }),
  };

  if (emailDelivery || githubDelivery) {
    const secrets = [];
    const channels = {};
    if (emailDelivery) {
      const resendApiKey = defineSecret("RESEND_API_KEY");
      secrets.push(resendApiKey);
      channels.email = { apiKey: () => resendApiKey.value() };
    }
    if (githubDelivery) {
      const githubToken = defineSecret("GITHUB_BUG_REPORT_TOKEN");
      secrets.push(githubToken);
      channels.github = { token: () => githubToken.value() };
    }
    let delivery = null;
    exported[BUG_REPORT_DELIVERY_EXPORT] = registrars.onDocumentCreated({
      document: "bugReports/{reportId}",
      region: REGION,
      retry: true,
      secrets,
      memory: "256MiB",
      timeoutSeconds: 60,
    }, async (event) => {
      const { createBugReportDelivery } = require("./delivery");
      const current = resolve();
      delivery ??= createBugReportDelivery({
        db: current.db, Timestamp: current.Timestamp, logger: current.logger, channels,
      });
      await delivery.deliverBugReport(event.params?.reportId);
    });
  }
  return exported;
}

module.exports = {
  BUG_REPORT_BASE_EXPORT_NAMES,
  BUG_REPORT_DELIVERY_EXPORT,
  createBugReportFunctions,
};
