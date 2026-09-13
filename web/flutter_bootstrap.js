{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
    // The localized Flutter startup is the only loader. No second HTML
    // composition, minimum display time, or delayed overlay removal.
  },
});
