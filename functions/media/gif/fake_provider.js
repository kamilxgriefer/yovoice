// A deterministic fixture catalog implementing the provider interface.
//
// THIS IS NOT FAKE DATA IN THE SENSE CLAUDE.md FORBIDS. It never reaches a
// user: `createGifProvider` throws unless FUNCTIONS_EMULATOR /
// FIRESTORE_EMULATOR_HOST / NODE_ENV=test is set, and production runs
// GIF_PROVIDER=none. Its purpose is that the entire pipeline — cache, rate
// limits, budget, rating re-filter, denylist, moderation, the client picker —
// is exercised end to end before a key exists, so the day the key arrives
// nothing about the system is being run for the first time.
//
// Its URLs point at `fake.invalid`, a domain reserved by RFC 2606 that can
// never resolve. A fixture must not cause a real network fetch.

"use strict";

const { GIF_PROVIDERS } = require("./gif_ref");
const { buildGifAsset, normalizeLimit } = require("./normalize");

const FAKE_ATTRIBUTION = Object.freeze({
  text: "Fixture catalog (no provider configured)",
  required: false,
});

/// `[id, title, rating, tags]`. Tags drive search so a query behaves like a
/// query rather than a substring match on the title.
const FIXTURES = Object.freeze([
  ["fakeCat01", "Happy cat", "g", "cat kot happy szczescie animal"],
  ["fakeCat02", "Cat typing fast", "g", "cat kot typing work"],
  ["fakeCat03", "Sleepy kitten", "g", "cat kot sleep spanie"],
  ["fakeDog01", "Dog says hello", "g", "dog pies hello czesc animal"],
  ["fakeDog02", "Excited puppy", "g", "dog pies excited happy"],
  ["fakeYes01", "Absolutely yes", "g", "yes tak agree approve"],
  ["fakeNo001", "Hard no", "g", "no nie disagree refuse"],
  ["fakeLol01", "Laughing out loud", "g", "lol laugh smiech funny"],
  ["fakeLol02", "Cannot stop laughing", "g", "lol laugh smiech funny"],
  ["fakeHug01", "Big hug", "g", "hug przytul love care"],
  ["fakeWav01", "Waving hello", "g", "wave hello czesc greeting"],
  ["fakeCry01", "Happy tears", "g", "cry lzy emotional happy"],
  ["fakeDan01", "Dance party", "g", "dance taniec party celebrate"],
  ["fakeDan02", "Victory dance", "g", "dance taniec win celebrate"],
  ["fakeThx01", "Thank you so much", "g", "thanks dzieki grateful"],
  ["fakeSry01", "So sorry", "g", "sorry przepraszam apology"],
  ["fakeWow01", "Mind blown", "g", "wow amazing zaskoczenie"],
  ["fakeOks01", "Okay then", "g", "ok okej fine agree"],
  ["fakeCel01", "Confetti celebration", "g", "celebrate party sukces"],
  ["fakeCof01", "Coffee time", "g", "coffee kawa morning"],
  ["fakeSlp01", "Falling asleep", "g", "sleep spanie tired"],
  ["fakeThk01", "Deep in thought", "g", "think myslenie hmm"],
  ["fakeRun01", "Running late", "g", "run biegnie late hurry"],
  ["fakeLov01", "Sending love", "g", "love milosc heart"],
  ["fakeFir01", "That is fire", "g", "fire ogien hot cool"],
  ["fakeClp01", "Slow clap", "g", "clap brawa applause"],
  ["fakeShk01", "Shaking head", "g", "no nie disagree head"],
  ["fakeNod01", "Nodding along", "g", "yes tak agree nod"],
  ["fakeWrk01", "Back to work", "g", "work praca busy"],
  ["fakeWin01", "We won", "g", "win wygrana celebrate sukces"],
  ["fakeMus01", "Music vibes", "g", "music muzyka dance"],
  ["fakeVoi01", "On the mic", "g", "voice glos mic speak"],
  ["fakeRoo01", "Room is live", "g", "live room pokoj voice"],
  ["fakeGrt01", "Good morning", "g", "morning dzien dobry greeting"],
  ["fakeNgt01", "Good night", "g", "night dobranoc sleep"],
  ["fakeStr01", "Star struck", "g", "star gwiazda wow"],
  // ---- Adversarial fixtures. Each one exists to prove a filter runs. ----
  // Not `g`: the response re-filter in catalog.js must drop it, and the
  // firestore.rules send check must refuse it even if it somehow leaked.
  ["fakeBad01", "Rated PG asset", "pg", "cat kot edge rating"],
  // No rating at all -> normalizeRating returns "unrated" -> also dropped.
  ["fakeBad02", "Unrated asset", "", "dog pies edge rating"],
  // Empty title -> sanitizeTitle's fallback must produce a renderable label.
  ["fakeEdg01", "", "g", "edge empty title"],
  // Over-long title -> must be truncated to MAX_GIF_TITLE_LENGTH.
  [
    "fakeEdg02",
    "A title so long that it exists purely to prove the hundred character " +
      "ceiling is applied on the way in and not merely on the way out",
    "g",
    "edge long title",
  ],
]);

function createFakeGifProvider({ now = () => Date.now() } = {}) {
  const assets = FIXTURES.map(([id, title, rating, tags]) => ({
    tags,
    asset: buildGifAsset({
      provider: GIF_PROVIDERS.fake,
      id,
      title,
      rating,
      previewUrl: `https://fake.invalid/preview/${id}.gif`,
      width: 200,
      height: 200,
      sourceUrl: null,
    }),
  })).filter((entry) => entry.asset !== null);

  function page(matching, { limit, cursor }) {
    const size = normalizeLimit(limit);
    const offset = Number.parseInt(cursor ?? "0", 10);
    const start = Number.isSafeInteger(offset) && offset >= 0 ? offset : 0;
    const slice = matching.slice(start, start + size);
    const consumed = start + slice.length;
    return {
      items: slice.map((entry) => entry.asset),
      nextCursor:
        slice.length > 0 && consumed < matching.length
          ? String(consumed)
          : null,
      fetchedAt: now(),
    };
  }

  return Object.freeze({
    id: GIF_PROVIDERS.fake,
    attribution: FAKE_ATTRIBUTION,
    isConfigured: true,
    async search({ query, limit, cursor } = {}) {
      const terms = String(query ?? "")
        .split(" ")
        .filter((term) => term.length > 0);
      const matching = assets.filter((entry) => {
        const haystack = `${entry.tags} ${entry.asset.title.toLowerCase()}`;
        return terms.every((term) => haystack.includes(term));
      });
      return page(matching, { limit, cursor });
    },
    async trending({ limit, cursor } = {}) {
      return page(assets, { limit, cursor });
    },
    async resolve({ id } = {}) {
      const found = assets.find((entry) => entry.asset.id === id);
      return { items: found ? [found.asset] : [], nextCursor: null };
    },
  });
}

module.exports = {
  FAKE_ATTRIBUTION,
  FIXTURES,
  createFakeGifProvider,
};
