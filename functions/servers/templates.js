const { fail } = require("../integrity/guards");
const { TEMPLATE_VERSION } = require("./contract");

// Seed content is navigation only: no people, conversations, events or media.
// Stable keys, not translated names, define retry and migration identities.
const TEMPLATES = Object.freeze({
  friends: [
    ["general", "text", "general", "ogólny"],
    ["memes", "text", "memes", "memy"],
    ["lounge", "voice", "Lounge", "Salon"],
    ["gaming", "voice", "Gaming", "Gaming"],
    ["events", "events", "Events", "Wydarzenia"],
    ["rules", "rules", "Rules", "Zasady"],
  ],
  community: [
    ["announcements", "announcements", "Announcements", "Ogłoszenia"],
    ["rules", "rules", "Rules", "Regulamin"],
    ["general", "text", "general", "ogólny"],
    ["questions", "questions", "Questions", "Pytania"],
    ["lounge", "voice", "Lounge", "Salon"],
    ["stage", "stage", "LIVE Stage", "Scena LIVE", "video"],
    ["events", "events", "Events", "Wydarzenia"],
  ],
  podcast: [
    ["studio", "stage", "LIVE Studio", "Studio LIVE", "audio"],
    ["episodes", "episodes", "Episodes", "Odcinki"],
    ["program", "events", "Program", "Program"],
    ["discussion", "text", "discussion", "dyskusje"],
    ["questions", "questions", "Questions", "Pytania"],
    ["announcements", "announcements", "Announcements", "Ogłoszenia"],
    ["rules", "rules", "Rules", "Zasady"],
  ],
  family: [
    ["family", "text", "family", "rodzinny"],
    ["lounge", "voice", "Lounge", "Salon"],
    ["calendar", "calendar", "Calendar", "Kalendarz"],
    ["memories", "memories", "Memories", "Wspomnienia"],
    ["shopping", "list", "Shopping list", "Lista zakupów"],
  ],
  company: [
    ["general", "text", "general", "ogólny"],
    ["announcements", "announcements", "Announcements", "Ogłoszenia"],
    ["team", "text", "team", "zespół"],
    ["projects", "text", "projects", "projekty"],
    ["hr", "text", "HR", "HR", null, true],
    ["boardroom", "text", "Management", "Zarząd", null, true],
    ["meeting", "meeting", "Meetings", "Spotkania"],
    ["board", "whiteboard", "Whiteboard", "Tablica"],
    ["files", "files", "Files", "Pliki"],
  ],
});
for (const rows of Object.values(TEMPLATES)) {
  for (const row of rows) Object.freeze(row);
  Object.freeze(rows);
}

function templateChannels(serverType, defaultLanguage, templateVersion = TEMPLATE_VERSION) {
  if (!Object.hasOwn(TEMPLATES, serverType) || templateVersion !== TEMPLATE_VERSION) {
    fail("invalid-argument", "This server template is unsupported.");
  }
  const polish = /^(pl(?:[-_].*)?|polish|polski)$/iu.test(defaultLanguage);
  return TEMPLATES[serverType].map(([seedKey, kind, english, pl, stageMode, restricted]) => ({
    seedKey,
    kind,
    name: polish ? pl : english,
    categoryId: null,
    accessMode: restricted ? "restricted" : "members",
    experience: kind === "stage" ? "broadcast" : ["voice", "meeting"].includes(kind) ? "community" : null,
    mediaMode: kind === "stage" ? stageMode : kind === "voice" ? "audio" : kind === "meeting" ? "meeting" : null,
  }));
}

module.exports = { TEMPLATES, templateChannels };
