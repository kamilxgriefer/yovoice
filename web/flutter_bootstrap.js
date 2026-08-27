{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();

    const splash = document.getElementById("yovoice-bootstrap");
    if (!splash) return;
    // runApp resolves when Flutter has scheduled its first frame. Give the
    // browser one paint to commit that frame underneath the bootstrap before
    // fading the cover; otherwise fast devices can reveal a single empty
    // canvas between the two surfaces.
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        splash.classList.add("boot-leaving");
        setTimeout(() => splash.remove(), 180);
      });
    });
  },
});
