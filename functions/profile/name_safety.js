// Reserved-name and tick-lookalike refusal (Premium Pages, ADR-233 §1.8).
//
// Pure: no SDK import. A Page is an account that reads "like a server", so a
// Page named "YO Voice Support", "Y0 Voice", "Official ✓" or a Cyrillic
// "УО Vоісе" would borrow trust it does not have. In v1 this refusal is
// enforced for PAGE accounts only: at managePageV1 create and resume, and on
// every updateMyDisplayName while a pages/{uid} document exists (paused or
// not). The tick work later extends it to every account in display_name.js.
//
// The comparison runs on a SKELETON, never on the raw string:
//
//   1. NFKC (full-width, circled and styled letters fold to ASCII), then NFD
//      with combining marks removed ("ó" -> "o");
//   2. the confusable map BEFORE lower-casing, then again after it: a capital
//      look-alike can lower-case into a letter that looks like something
//      else (Greek "Υ" is a Latin Y but lower-cases to "υ", a u; Cherokee
//      capitals lower-case into the Cherokee small block), so capitals are
//      mapped while they still look like the Latin capital. The map covers
//      Cyrillic, Greek, Armenian, Cherokee and Lisu look-alikes, the IPA /
//      phonetic small capitals ("ʏᴏ ᴠᴏɪᴄᴇ"), leetspeak digits and symbols
//      ("0" -> "o", "1" / "l" / "|" / "!" -> "i", "@" -> "a" ...);
//   4. "rn" -> "m" and "vv" -> "w", the two common multi-letter look-alikes;
//   5. split into tokens on anything that is not a letter or digit, and glue
//      runs of single-character tokens back together ("V I P" -> "vip").
//
// Both the candidate name and every reserved word go through the same
// skeleton, so the map may over-merge (it does: "l" and "i" collide) without
// ever letting a reserved word through. Over-refusal is the safe direction;
// the refusal copy tells the owner to pick another name.

const PAGE_NAME_RESERVED_REASON = "pageNameReserved";

// Check marks and badge look-alikes (badge-audit §3.6). A purple circle or a
// purple heart is only a look-alike NEXT TO a check, and every check here is
// refused on its own, so the pair is covered.
// The square root "√" and "⍻" read as a tick in most fonts.
const TICK_LOOKALIKES = /[✓✔✅☑√⍻\u{1F5F8}\u{1F5F9}\u{10102}]/u;

const CONFUSABLES = new Map(Object.entries({
  // Cyrillic
  "а": "a", "б": "b", "в": "b", "г": "r", "е": "e", "ё": "e", "з": "3",
  "и": "u", "й": "u", "к": "k", "л": "n", "м": "m", "н": "h", "о": "o",
  "п": "n", "р": "p", "с": "c", "т": "t", "у": "y", "ф": "o", "х": "x",
  "ц": "u", "ч": "4", "ш": "w", "щ": "w", "ь": "b", "ы": "bi", "ъ": "b",
  "э": "e", "ю": "io", "я": "r", "і": "i", "ї": "i", "ј": "j", "ѕ": "s",
  "ԁ": "d", "ԛ": "q", "ԝ": "w", "ӏ": "i", "ѵ": "v", "ү": "y", "һ": "h",
  "ɡ": "g", "ɑ": "a", "ǀ": "i",
  // Greek
  "α": "a", "β": "b", "γ": "y", "δ": "d", "ε": "e", "η": "n", "ι": "i",
  "κ": "k", "μ": "u", "ν": "v", "ο": "o", "ρ": "p", "σ": "o", "ς": "c",
  "τ": "t", "υ": "u", "χ": "x", "ω": "w",
  // Greek and Cyrillic CAPITALS whose lower case looks like another letter
  // (applied before lower-casing): "Η" is H but "η" reads n, "Υ" is Y but
  // "υ" reads u, "Μ" is M but "μ" reads u, "Ν" is N but "ν" reads v.
  "Η": "h", "Υ": "y", "Μ": "m", "Ν": "n", "Ζ": "z", "Ϲ": "c", "Ј": "j",
  // Armenian
  "Օ": "o", "օ": "o", "ս": "u", "ո": "n", "հ": "h", "ց": "g", "զ": "q",
  "ա": "w", "Լ": "l", "լ": "l",
  // Cherokee capitals (they lower-case into U+AB70..U+ABBF, so they are
  // mapped before lower-casing)
  "Ꭺ": "a", "Ᏼ": "b", "Ꮟ": "b", "Ꮯ": "c", "Ꭰ": "d", "Ꭼ": "e", "Ꮐ": "g",
  "Ꮋ": "h", "Ꮒ": "h", "Ꭵ": "i", "Ꭻ": "j", "Ꮶ": "k", "Ꮮ": "l", "Ꮇ": "m",
  "Ꮲ": "p", "Ꭱ": "r", "Ꮪ": "s", "Ꮥ": "s", "Ꭲ": "t", "Ꮩ": "v", "Ꮃ": "w",
  "Ꮤ": "w", "Ꭹ": "y", "Ꮍ": "y", "Ꮓ": "z", "Ꮎ": "o",
  // Lisu (capital-Latin look-alikes; no case)
  "ꓮ": "a", "ꓐ": "b", "ꓚ": "c", "ꓓ": "d", "ꓰ": "e", "ꓝ": "f", "ꓖ": "g",
  "ꓧ": "h", "ꓲ": "i", "ꓙ": "j", "ꓗ": "k", "ꓡ": "l", "ꓟ": "m", "ꓠ": "n",
  "ꓳ": "o", "ꓑ": "p", "ꓣ": "r", "ꓢ": "s", "ꓔ": "t", "ꓴ": "u", "ꓦ": "v",
  "ꓪ": "w", "ꓫ": "x", "ꓬ": "y", "ꓜ": "z",
  // Latin / IPA small capitals (U+1D00 block and the IPA letters)
  "ᴀ": "a", "ᴁ": "ae", "ʙ": "b", "ᴃ": "b", "ᴄ": "c", "ᴅ": "d", "ᴆ": "d",
  "ᴇ": "e", "ꜰ": "f", "ɢ": "g", "ʜ": "h", "ɪ": "i", "ᴉ": "i", "ᴊ": "j",
  "ᴋ": "k", "ʟ": "l", "ᴌ": "l", "ᴍ": "m", "ɴ": "n", "ᴎ": "n", "ᴏ": "o",
  "ᴐ": "c", "ᴘ": "p", "ꞯ": "q", "ʀ": "r", "ᴙ": "r", "ꜱ": "s", "ᴛ": "t",
  "ᴜ": "u", "ᴠ": "v", "ᴡ": "w", "ʏ": "y", "ᴢ": "z",
  // Latin extensions that do not decompose under NFD
  "ł": "l", "ø": "o", "đ": "d", "ħ": "h", "ı": "i", "ȷ": "j", "ß": "ss",
  "æ": "ae", "œ": "oe", "þ": "p",
  // Digits and symbols
  "0": "o", "1": "i", "2": "z", "3": "e", "4": "a", "5": "s", "6": "b",
  "7": "t", "8": "b", "9": "g", "@": "a", "$": "s", "|": "i", "!": "i",
  "€": "e", "£": "l", "¡": "i",
  // Final fold: "l" and "i" are one glyph in many fonts ("VlP", "Offlcial").
  "l": "i",
}));
// Cherokee small letters (U+AB70..U+ABBF, U+13F8..U+13FD) are the same glyphs
// as the capitals: each mapped capital's lower case maps the same way.
for (const [character, latin] of [...CONFUSABLES]) {
  const code = character.codePointAt(0);
  if (code >= 0x13a0 && code <= 0x13f5) CONFUSABLES.set(character.toLowerCase(), latin);
}

function skeletonCharacters(value) {
  let out = "";
  for (const character of value) {
    const mapped = CONFUSABLES.get(character) ?? character;
    // A mapping can itself produce a mapped character ("£" -> "l" -> "i").
    out += [...mapped].map((part) => CONFUSABLES.get(part) ?? part).join("");
  }
  return out;
}

/// The token skeleton of `value`. Pure and total: a non-string is [].
function nameSkeletonTokens(value) {
  if (typeof value !== "string") return [];
  const stripMarks = (text) => text.normalize("NFD").replace(/\p{M}+/gu, "");
  // Map before lower-casing (capitals), then again after it.
  const capitals = skeletonCharacters(stripMarks(value.normalize("NFKC")));
  const folded = stripMarks(capitals.toLocaleLowerCase("en-US"));
  const mapped = skeletonCharacters(folded)
    .replace(/rn/gu, "m")
    .replace(/vv/gu, "w");
  const raw = mapped.split(/[^\p{L}\p{N}]+/u).filter((token) => token.length > 0);
  // Glue runs of single-character tokens: "v.i.p", "Y O Voice" -> "yo", ...
  const tokens = [];
  let run = "";
  for (const token of raw) {
    if ([...token].length === 1) {
      run += token;
      continue;
    }
    if (run) tokens.push(run);
    run = "";
    tokens.push(token);
  }
  if (run) tokens.push(run);
  return tokens;
}

function skeletonOf(word) {
  return nameSkeletonTokens(word).join("");
}

// Refused anywhere in the whole glued name ("yovoiceteam", "the yo voice").
const RESERVED_ANYWHERE = Object.freeze(["YO Voice", "YOVoice"].map(skeletonOf));

// Refused as a whole token.
const RESERVED_TOKENS = Object.freeze([
  "VIP", "Admin", "Admins", "Administrator", "Administracja", "Moderator",
  "Moderators", "Moderacja", "Support", "Pomoc", "Wsparcie", "Official",
  "Oficjalny", "Oficjalna", "Oficjalne", "Oficjalnie", "Verified",
  "Zweryfikowany", "Zweryfikowana", "Zweryfikowane", "Staff",
].map(skeletonOf));

// Refused as a token prefix or suffix ("OfficialShop", "TeamAdmin",
// "yovoicemoderators"). Deliberately NOT "vip", "support" or "pomoc": as
// affixes they are ordinary words ("Vipassana", "Supporters", "Pomocnik").
const RESERVED_AFFIXES = Object.freeze([
  "Official", "Oficjaln", "Admin", "Moderator", "Verified", "Zweryfikowan",
].map(skeletonOf));

/**
 * Why `name` cannot be used for a Page, or null when it can:
 *   "lookalike" - it carries a check mark or badge look-alike;
 *   "reserved"  - its skeleton contains a reserved word.
 */
function pageNameViolation(name) {
  if (typeof name !== "string") return "reserved";
  if (TICK_LOOKALIKES.test(name.normalize("NFKC"))) return "lookalike";
  const tokens = nameSkeletonTokens(name);
  const glued = tokens.join("");
  if (RESERVED_ANYWHERE.some((word) => glued.includes(word))) return "reserved";
  for (const token of tokens) {
    if (RESERVED_TOKENS.includes(token)) return "reserved";
    if (RESERVED_AFFIXES.some((word) =>
      token.startsWith(word) || token.endsWith(word))) {
      return "reserved";
    }
  }
  return null;
}

function pageNameAllowed(name) {
  return pageNameViolation(name) === null;
}

module.exports = {
  PAGE_NAME_RESERVED_REASON,
  RESERVED_AFFIXES,
  RESERVED_ANYWHERE,
  RESERVED_TOKENS,
  nameSkeletonTokens,
  pageNameAllowed,
  pageNameViolation,
};
