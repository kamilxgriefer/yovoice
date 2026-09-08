/**
 * A Storage bucket that is resolved on first use.
 *
 * firebase-admin constructs its Storage service — and with it requires
 * @google-cloud/storage — inside getStorage(). Three runtimes used to call
 * getStorage().bucket() while functions/index.js was being evaluated, so
 * every cold start paid for the client library whether or not the request
 * touched an object. This wrapper defers that to the first request that
 * does.
 *
 * It forwards exactly the members the storage adapters and media probes use
 * today: `name`, `file()` and `getFiles()`. Any new bucket method an adapter
 * starts calling must be added here — it would otherwise throw at call time,
 * which unit tests with real buckets catch and the module-graph test does
 * not. Adapters that guard on `bucket?.file` keep passing because `file` is a
 * function.
 */
function createLazyBucket(resolve) {
  if (typeof resolve !== "function") {
    throw new TypeError("A bucket resolver function is required.");
  }
  let bucket = null;
  const real = () => (bucket ??= resolve());
  return Object.freeze({
    get name() {
      return real().name;
    },
    file: (...args) => real().file(...args),
    getFiles: (...args) => real().getFiles(...args),
  });
}

module.exports = { createLazyBucket };
