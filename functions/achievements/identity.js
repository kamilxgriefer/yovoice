const FIREBASE_UID_MAX_LENGTH = 128;
const CONTROL_CHARACTER_PATTERN = /\p{Cc}/u;

// Firebase Auth UIDs are opaque, case-sensitive identifiers. Never trim,
// case-fold or Unicode-normalise them: doing so can alias one account to
// another before an Admin SDK write.
function isValidOpaqueUid(value) {
  return typeof value === "string" &&
    value.length >= 1 &&
    value.length <= FIREBASE_UID_MAX_LENGTH &&
    !value.includes("/") &&
    !CONTROL_CHARACTER_PATTERN.test(value);
}

module.exports = {
  FIREBASE_UID_MAX_LENGTH,
  isValidOpaqueUid,
};
