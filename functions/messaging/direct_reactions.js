// The reaction picker shared by direct messages, Server channel messages and
// the Server reactor list (ADR-216, ADR-230). A dependency-free leaf, so the
// likers modules can order reactions without loading the direct-messaging
// graph. The order is load-bearing: it is the Server reactor list's sort key
// and the index stored in its page cursors.
const ALLOWED_DIRECT_REACTIONS = Object.freeze([
  "❤️",
  "😂",
  "🔥",
  "😮",
  "😢",
  "👍",
]);

module.exports = { ALLOWED_DIRECT_REACTIONS };
