// livekit-server-sdk is required on first use, not at module load. Every
// Cloud Function in this codebase evaluates functions/index.js on a cold
// start, and only the token, call, control-plane and webhook paths ever use
// the SDK; a Reel reservation or a chat open should not pay for it.
// test/cold_start_module_graph.test.js pins that requiring index.js leaves
// the SDK out of require.cache.
let sdk = null;

function loadLiveKitSdk() {
  return (sdk ??= require("livekit-server-sdk"));
}

module.exports = { loadLiveKitSdk };
