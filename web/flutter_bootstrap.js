{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();

    const splash = document.getElementById("yovoice-bootstrap");
    if (!splash) return;
    requestAnimationFrame(() => {
      splash.classList.add("boot-leaving");
      setTimeout(() => splash.remove(), 180);
    });
  },
});
