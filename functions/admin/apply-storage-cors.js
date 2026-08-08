const { onRequest } = require("firebase-functions/v2/https");
const { getStorage } = require("firebase-admin/storage");
const { logger } = require("firebase-functions/v2");

const REGION = "europe-west1";

/**
 * ONE-SHOT maintenance endpoint — delete after running once.
 *
 * Root cause it fixes: the default bucket
 * (yovoice-ec54a.firebasestorage.app) has no CORS configuration. Firebase
 * Storage's API front-end adds Access-Control-Allow-Origin to ERROR
 * responses, but successful `alt=media` downloads are served with the
 * BUCKET's CORS config — i.e. none — so browsers block every real image
 * byte, and no Storage-hosted image has ever rendered in the web app.
 *
 * Takes no input and performs exactly one fixed, idempotent action, so
 * exposing it unauthenticated for one invocation carries no risk beyond
 * applying this intended config.
 */
const applyStorageCors = onRequest({ region: REGION }, async (req, res) => {
  const bucket = getStorage().bucket();
  const cors = [
    {
      origin: ["*"],
      method: ["GET", "HEAD"],
      maxAgeSeconds: 3600,
      responseHeader: ["Content-Type", "Range"],
    },
  ];
  await bucket.setCorsConfiguration(cors);
  const [metadata] = await bucket.getMetadata();
  logger.info("bucket CORS applied", { cors: metadata.cors });
  res.json({ applied: metadata.cors });
});

module.exports = { applyStorageCors };
