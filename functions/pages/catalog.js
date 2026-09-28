// Server-owned Page categories (Premium Pages, ADR-233 §1.8). Pure.
//
// The client renders a localized label per key; the key set is the contract.
// Deliberately absent: alcohol, tobacco and vapes, gambling, weapons, adult
// services, dating, crypto and investment. Posts promoting them are
// removable under the `restrictedCategory` moderation reason.

const PAGE_KINDS = Object.freeze(["business", "community"]);

const BUSINESS_CATEGORIES = Object.freeze([
  "cafe_restaurant",
  "shop",
  "beauty_wellness",
  "sport_fitness",
  "education",
  "music_arts",
  "media_podcast",
  "services",
  "tech",
  "local_travel",
  "other_business",
]);

const COMMUNITY_CATEGORIES = Object.freeze([
  "sport",
  "music",
  "gaming",
  "books_learning",
  "hobby_crafts",
  "local_neighbourhood",
  "fan_club",
  "charity_cause",
  "other_community",
]);

const PAGE_CATEGORIES = Object.freeze({
  business: BUSINESS_CATEGORIES,
  community: COMMUNITY_CATEGORIES,
});

function pageCategoryAllowed(kind, category) {
  return PAGE_KINDS.includes(kind) &&
    typeof category === "string" &&
    PAGE_CATEGORIES[kind].includes(category);
}

module.exports = {
  BUSINESS_CATEGORIES,
  COMMUNITY_CATEGORIES,
  PAGE_CATEGORIES,
  PAGE_KINDS,
  pageCategoryAllowed,
};
