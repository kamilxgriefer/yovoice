// Query denylist — layer 3 of four.
//
// `rating=g` (layer 1) and the response re-filter (layer 2) both trust the
// provider to have rated an asset correctly. This layer does not: it refuses
// the query before it ever reaches the provider, so the picker cannot be used
// as a pornography search box even if the provider's own filter has a hole.
//
// It is deliberately SHORT, STATIC and REVIEWABLE rather than clever. A long
// generated list produces false positives on ordinary words in two languages
// and nobody can audit it; a regex-heavy one produces false positives nobody
// can predict. Matching is on whole tokens of the already-normalized query,
// which is why "assassin" does not trip "ass" and "Scunthorpe" is fine.

"use strict";

/// English and Polish, because the app ships in both and a filter that only
/// speaks English is a filter with a documented bypass.
const DENIED_TERMS = Object.freeze(new Set([
  "porn",
  "porno",
  "pornhub",
  "porno",
  "xxx",
  "nsfw",
  "nude",
  "nudes",
  "naked",
  "nago",
  "nagie",
  "sex",
  "seks",
  "sexy",
  "seksowne",
  "hentai",
  "boobs",
  "cycki",
  "tits",
  "penis",
  "dick",
  "cock",
  "pussy",
  "cipka",
  "anal",
  "blowjob",
  "orgasm",
  "orgazm",
  "masturbation",
  "masturbacja",
  "escort",
  "onlyfans",
  "camgirl",
  "fetish",
  "fetysz",
  "bdsm",
  "rape",
  "gwalt",
  "incest",
  "kazirodztwo",
  "loli",
  "shota",
  "cp",
  "underage",
  "nieletnie",
  "nieletni",
  "gore",
  "beheading",
  "suicide",
  "samobojstwo",
  "selfharm",
]));

/// Two-word phrases that are only a problem together. Kept separate so
/// "child" and "teen" on their own — both perfectly ordinary search terms —
/// are never refused.
const DENIED_PHRASES = Object.freeze([
  "child porn",
  "teen porn",
  "kill yourself",
  "how to die",
]);

/// Letters that carry no Unicode decomposition, so NFD leaves them alone.
///
/// Polish `ł` is the one that matters here and it is the one that bit: it is a
/// single codepoint with no combining form, so a diacritic fold left "gwałt"
/// intact and the `[^a-z0-9 ]` sweep then turned it into "gwa t", which
/// matched nothing. Found by test/gif_cache_and_limits.test.js. The rest are
/// included because the same class of miss applies to them.
const UNDECOMPOSABLE_LETTERS = Object.freeze({
  ł: "l",
  Ł: "l",
  ø: "o",
  Ø: "o",
  đ: "d",
  Đ: "d",
  ß: "ss",
  æ: "ae",
  Æ: "ae",
  œ: "oe",
  Œ: "oe",
});

/// Diacritic-folded so the Polish list catches its own accented spellings
/// without needing every variant enumerated: "gwałt" folds to "gwalt".
function foldQuery(query) {
  return query
    .toLowerCase()
    .replace(
      /[łŁøØđĐßæÆœŒ]/gu,
      (letter) => UNDECOMPOSABLE_LETTERS[letter] ?? letter,
    )
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .replace(/[^a-z0-9 ]+/gu, " ")
    .replace(/\s+/gu, " ")
    .trim();
}

/// True when this query must not reach the provider.
///
/// The caller answers with an EMPTY RESULT SET and neutral copy, never with an
/// error and never with an explanation of why. Telling somebody which term
/// tripped the filter is a map of the filter.
function isDeniedQuery(normalizedQuery) {
  if (typeof normalizedQuery !== "string" || normalizedQuery.length === 0) {
    return false;
  }
  const folded = foldQuery(normalizedQuery);
  if (folded.length === 0) return false;
  for (const phrase of DENIED_PHRASES) {
    if (folded.includes(phrase)) return true;
  }
  for (const token of folded.split(" ")) {
    if (DENIED_TERMS.has(token)) return true;
  }
  return false;
}

module.exports = {
  DENIED_PHRASES,
  DENIED_TERMS,
  foldQuery,
  isDeniedQuery,
};
