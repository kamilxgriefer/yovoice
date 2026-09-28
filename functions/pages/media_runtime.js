// The default Storage adapter and trusted probe for Page post media, over ONE
// lazy bucket. Nothing is constructed at module load: the bucket (and with it
// @google-cloud/storage) is resolved on the first object access, which keeps
// the cold-start module graph free of the Storage SDK (utils/lazy_bucket.js).

const { createPagesMediaStorageAdapter } = require("./media_storage");

let dependencies = null;

function defaultPagesMediaDependencies() {
  if (dependencies === null) {
    const { createLazyBucket } = require("../utils/lazy_bucket");
    // The Reel / direct-message trusted probe: magic-number sniff, and for
    // audio the track set and a duration measured from the object itself.
    const { createTrustedGcsMediaProbe } = require("../reels/probe");
    const bucket = createLazyBucket(() => require("firebase-admin/storage").getStorage().bucket());
    dependencies = Object.freeze({
      storage: createPagesMediaStorageAdapter(bucket),
      probeMedia: createTrustedGcsMediaProbe(bucket),
    });
  }
  return dependencies;
}

module.exports = { defaultPagesMediaDependencies };
