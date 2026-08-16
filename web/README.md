# Web entry & favicon

`index.html` is the Flutter web entry. Everything else in this folder is
the browser-tab / PWA icon set.

## Source of truth

The icons are **not** drawn here. Every file is a straight LANCZOS
downscale of the marketing site's canonical square icon:

```
/Users/kamiljaguszewski/yovoice-website/src/app/icon.png   (512x512, transparent)
  └─ itself: public/logos/yo-voice-symbol.png (362x375) centred on a
     512x512 transparent canvas — 417x432 of artwork, ~8% padding
```

The generated files are committed, so this repo builds on its own
without the website checked out. The website repo stays the place the
artwork itself changes.

| File | Size | Used by |
| --- | --- | --- |
| `favicon.ico` | 16/32/48/64/128/256 | `shortcut icon`, bare `/favicon.ico` |
| `favicon-16x16.png` | 16 | tab strip |
| `favicon-32x32.png` | 32 | tab strip / retina |
| `favicon-96x96.png` | 96 | bookmarks, shortcuts |
| `apple-touch-icon.png` | 180 | iOS home screen |
| `web-app-manifest-192x192.png` | 192 | `site.webmanifest` |
| `web-app-manifest-512x512.png` | 512 | `site.webmanifest` (also the master) |

## Why the old set was replaced

The previous icons came from RealFaviconGenerator and were built from a
version of the mark with a **solid black square baked in** — fully
opaque at every size, which showed as a dark tile around the symbol in
the tab strip while the landing page's tab showed a clean transparent
mark. `favicon.svg` (a 1.6 MB traced raster), `favicon.zip` (the
generator bundle), `favicon.png`, and the `flutter create` leftovers
(`manifest.json` + `icons/Icon-*.png`, which still carried "A new
Flutter project" and Flutter's `#0175C2` theme and were referenced by
nothing) were removed with them. `site.webmanifest` is the only manifest.

`purpose` is `any`, not `maskable`: the artwork is transparent with only
~8% padding, so a maskable declaration would let the platform crop into
the mark.

## Regenerating

```bash
python3 - <<'PY'
from PIL import Image
master = Image.open(
    "/Users/kamiljaguszewski/yovoice-website/src/app/icon.png"
).convert("RGBA")
for size, path in [
    (512, "web/web-app-manifest-512x512.png"),
    (192, "web/web-app-manifest-192x192.png"),
    (180, "web/apple-touch-icon.png"),
    (96,  "web/favicon-96x96.png"),
    (32,  "web/favicon-32x32.png"),
    (16,  "web/favicon-16x16.png"),
]:
    img = master if size == 512 else master.resize((size, size), Image.LANCZOS)
    img.save(path, "PNG", optimize=True)
master.save("web/favicon.ico", format="ICO",
            sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])
PY
```

Then **bump `?v=` in `index.html` and `site.webmanifest`**. Browsers and
the Hosting CDN cache icons aggressively; without the bump a deploy can
keep serving the old mark. `firebase.json` also sends `no-cache` for
these specific filenames so a future change propagates on reload.

## Native and desktop launchers

The same transparent master is the Android adaptive foreground and the
in-app compact mark. App Store, legacy Android, macOS and Windows icons use
`assets/images/app-store-icon.png`: the identical favicon artwork, enlarged
slightly for launcher legibility, on a full-bleed `#0B1026` navy canvas.
Apple requires an opaque App Store icon;
the canvas replaces transparency only and must never contain an additional
black square around the mark. Regenerate Android and iOS assets with
`dart run flutter_launcher_icons` after changing the master.
