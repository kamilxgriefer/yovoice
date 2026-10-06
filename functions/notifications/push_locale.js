/**
 * Server-side push localisation (ADR-237).
 *
 * Until build 42 every push title and body was English for every recipient.
 * The client now stores its app language on `users/{uid}.appLanguage` (one of
 * the 43 selectable locale keys; rules validate the value) and the push
 * boundary — which already reads that document for the preferences — picks
 * the recipient's template here.
 *
 * `push_copy.json` is GENERATED from the app's own translation catalog by
 * `test/push_copy_export_test.dart` (run it with
 * `--dart-define=UPDATE_PUSH_COPY=true` to rewrite the file), so a push says
 * exactly what the bell row says in the same language and no sentence is
 * translated twice. It carries the 42 non-English locales; English is
 * `PUSH_TITLES` in push.js and the defaults in push_payload.js, and is used
 * ONLY when the recipient's language is unknown (an account that has not
 * opened build 42 yet) or is English.
 *
 * Pure: no SDK import, no I/O after the first require.
 */
const COPY = require("./push_copy.json");

const TRANSLATED_PUSH_LOCALES = Object.freeze([...COPY.locales]);
const PUSH_LOCALES = Object.freeze(["en", ...TRANSLATED_PUSH_LOCALES]);
const PUSH_TEMPLATE_IDS = Object.freeze(Object.keys(COPY.templates).sort());
const PLACEHOLDER = /\{(actor|label)\}/gu;

/** One of the 43 locale keys, or null for anything else. */
function normalizePushLocale(value) {
  if (typeof value !== "string" || value.length === 0 || value.length > 12) {
    return null;
  }
  return PUSH_LOCALES.includes(value) ? value : null;
}

/** The language a recipient's push is written in. Unknown means English. */
function recipientPushLocale(userData) {
  return normalizePushLocale(userData?.appLanguage) ?? "en";
}

// Types whose title has a second form when the row carries a label.
const LABELLED_TYPES = Object.freeze([
  "clubInvite",
  "clubInviteAccepted",
  "roomInvite",
  "broadcastInvite",
  "liveStarted",
  "mention",
  "reply",
  "serverEventReminder",
  "serverRole",
  "achievementUnlocked",
]);
const PLAIN_TYPES = Object.freeze([
  "friendRequest",
  "friendAccepted",
  "follow",
  "directMessage",
  "momentComment",
  "reelComment",
  "commentMention",
  "pagePostComment",
  "pagePostPublished",
]);

/**
 * The template a (type, label) pair uses, or null when the title is not a
 * template at all: a `system` row and a labelled `moderation` row carry
 * server-authored text that is passed through as written.
 */
function pushTitleTemplateId(type, label) {
  const hasLabel = typeof label === "string" && label.length > 0;
  if (PLAIN_TYPES.includes(type)) return type;
  if (LABELLED_TYPES.includes(type)) return hasLabel ? `${type}.label` : type;
  if (type === "directCall") {
    return label === "Incoming video call" ? "directCall.video" : "directCall";
  }
  if (type === "missedCall") {
    return label === "Missed video call" ? "missedCall.video" : "missedCall";
  }
  if (type === "moderation") return hasLabel ? null : "moderation";
  return null;
}

function templateText(id, locale) {
  const text = COPY.templates[id]?.[locale];
  return typeof text === "string" && text.length > 0 ? text : null;
}

/** Single pass: braces inside a display name or a label stay verbatim. */
function fillTemplate(template, values) {
  return template.replace(PLACEHOLDER, (_match, name) => values[name] ?? "");
}

/**
 * The localized title, or null when the caller must use the English builder
 * (English recipient, pass-through type, or a template this build of the
 * table does not carry).
 */
function localizedPushTitle({ type, locale, actorName, targetLabel }) {
  if (locale === "en" || !TRANSLATED_PUSH_LOCALES.includes(locale)) return null;
  const id = pushTitleTemplateId(type, targetLabel);
  if (id === null) return null;
  const template = templateText(id, locale);
  if (template === null) return null;
  const actor = typeof actorName === "string" && actorName.trim().length > 0
    ? actorName.trim()
    : templateText("actor.unknown", locale) ?? "YO Voice";
  return fillTemplate(template, {
    actor,
    label: typeof targetLabel === "string" ? targetLabel : "",
  });
}

const SURFACE_TEMPLATES = Object.freeze({
  defaultBody: "body.default",
  incomingCallTitle: "call.incoming.title",
  incomingCallBody: "call.incoming.body",
  missedCallTitle: "call.missed.title",
  missedCallBody: "call.missed.body",
});

/**
 * The generic lock-screen sentences in `locale`, or null for English (the
 * payload builder's own defaults). A sentence the table lacks is left out so
 * the builder's English default fills that one slot.
 */
function localizedPushSurface(locale) {
  if (locale === "en" || !TRANSLATED_PUSH_LOCALES.includes(locale)) return null;
  const surface = {};
  for (const [key, id] of Object.entries(SURFACE_TEMPLATES)) {
    const text = templateText(id, locale);
    if (text !== null) surface[key] = text;
  }
  return surface;
}

module.exports = {
  LABELLED_TYPES,
  PLAIN_TYPES,
  PUSH_LOCALES,
  PUSH_TEMPLATE_IDS,
  SURFACE_TEMPLATES,
  TRANSLATED_PUSH_LOCALES,
  fillTemplate,
  localizedPushSurface,
  localizedPushTitle,
  normalizePushLocale,
  pushTitleTemplateId,
  recipientPushLocale,
};
