// YO Voice Originals — a credential-free, first-party GIF provider.
//
// The animated files ship in the Flutter asset bundle. The provider returns
// canonical `asset://yovoice/gifs/<id>.gif` identifiers, so search, selection,
// moderation and authoritative sends use the same pipeline as a remote
// provider without exposing a viewer's IP address or requiring a third-party
// account. Older clients safely render the stored text fallback.

"use strict";

const { GIF_PROVIDERS } = require("./gif_ref");
const { buildGifAsset, normalizeLimit } = require("./normalize");

const YOVOICE_ATTRIBUTION = Object.freeze({
  text: "YO Voice Originals",
  required: false,
});

// [id, title, tags]. Every animation is created for YO Voice and rated G.
// Tags include the shipped English and Polish search vocabulary.
const YOVOICE_GIFS = Object.freeze([
  ["yoLove01", "Sending love", "love heart milosc serce kocham"],
  ["yoLol001", "Laughing out loud", "lol laugh funny smiech zabawne"],
  ["yoWow001", "Wow", "wow amazing surprise super zaskoczenie"],
  ["yoYes001", "Absolutely yes", "yes tak agree zgoda jasne"],
  ["yoNo0001", "Hard no", "no nope nie disagree odmowa"],
  ["yoHey001", "Hey there", "hey hello hi czesc witaj"],
  ["yoThx001", "Thank you", "thanks thank you dzieki dziekuje"],
  ["yoClap01", "Bravo", "bravo clap applause brawa gratulacje"],
  ["yoParty1", "Party time", "party dance celebrate impreza taniec swieto"],
  ["yoHug001", "Big hug", "hug care przytul usciski"],
  ["yoFire01", "That is fire", "fire hot cool ogien sztos"],
  ["yoCool01", "So cool", "cool great super swietne"],
  ["yoMorn01", "Good morning", "morning hello dzien dobry rano"],
  ["yoNight1", "Good night", "night sleep dobranoc noc spanie"],
  ["yoMic001", "On air", "voice mic microphone live glos mikrofon"],
  ["yoWin001", "We won", "win success celebrate wygrana sukces"],
]);

// The app sends Unicode search text. Fold Polish diacritics for matching while
// retaining the original query in the server's normalization/cache layer, so
// natural input such as "dziękuję" finds the same entry as "dziekuje".
function foldSearchText(value) {
  return String(value ?? "")
    .normalize("NFD")
    .toLowerCase()
    .replace(/\p{Diacritic}/gu, "")
    .replace(/ł/gu, "l");
}

function createYovoiceGifProvider({ now = () => Date.now() } = {}) {
  const entries = YOVOICE_GIFS.map(([id, title, tags]) => ({
    searchText: foldSearchText(`${tags} ${title}`),
    asset: buildGifAsset({
      provider: GIF_PROVIDERS.yovoice,
      id,
      title,
      rating: "g",
      previewUrl: `asset://yovoice/gifs/${id}.gif`,
      width: 320,
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
    id: GIF_PROVIDERS.yovoice,
    attribution: YOVOICE_ATTRIBUTION,
    isConfigured: true,
    async search({ query, limit, cursor } = {}) {
      const terms = foldSearchText(query)
        .split(" ")
        .filter((term) => term.length > 0);
      const matching = entries.filter((entry) => {
        return terms.every((term) => entry.searchText.includes(term));
      });
      return page(matching, { limit, cursor });
    },
    async trending({ limit, cursor } = {}) {
      return page(entries, { limit, cursor });
    },
    async resolve({ id } = {}) {
      const found = entries.find((entry) => entry.asset.id === id);
      return { items: found ? [found.asset] : [], nextCursor: null };
    },
  });
}

module.exports = {
  YOVOICE_ATTRIBUTION,
  YOVOICE_GIFS,
  createYovoiceGifProvider,
};
