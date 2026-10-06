# Paca brand kit

Original kit 1.0 · 3 October 2026. Native app icon source added 5 October 2026.

Open [START-HERE.html](START-HERE.html) for the visual asset library, or [the PDF guide](guidelines/paca-brand-guide.pdf) for the shareable guidelines.

Paca is a native macOS client for Herdr. The identity combines an alpaca mascot, a lowercase wordmark and a simple one-color symbol. Lavender is the primary brand color. Mint and charcoal are alternate backgrounds. The signature composition lets the alpaca's neck continue out of the bottom or side of a window.

## Choose an asset

| Use | File |
| --- | --- |
| Native macOS app icon source | `app-icons/Paca.icon/` |
| Native appearance previews | `app-icons/native-previews/` |
| Original static macOS icons | `app-icons/Paca-lavender.icns`, `Paca-mint.icns`, `Paca-charcoal.icns` |
| Original static Xcode asset set | `app-icons/PacaAssets.xcassets/AppIcon.appiconset/` |
| macOS menu bar | `toolbar/PacaTemplate.imageset/` |
| Toolbar in a web app | `toolbar/paca-template.svg` |
| One-color symbol | `marks/paca-symbol-ink.svg` or `paca-symbol-white.svg` |
| Main logo on light backgrounds | `logos/paca-lockup-ink.svg` |
| Main logo on dark backgrounds | `logos/paca-lockup-cream.svg` |
| Scalable one-color logo | `logos/paca-lockup-mono-ink.svg` or `paca-lockup-mono-cream.svg` |
| Wordmark only | `logos/paca-wordmark-ink.svg` |
| Stacked logo | `logos/paca-stacked-ink.svg` |
| Standalone mascot | `mascot/paca-mascot.png` |
| Peeking mascot, transparent | `mascot/paca-peeking-transparent.png` |
| Favicon | `web/favicon.svg`, `web/favicon.ico` |
| Open Graph image | `social/paca-open-graph.png` |
| Wide banner | `social/paca-banner.png` |
| Square social graphic | `social/paca-square.png` |
| Color tokens | `tokens/paca.css`, `tokens/palette.json`, `tokens/PacaBrand.swift` |

## File formats

- The small symbol, wordmarks and mono lockups are genuine vector paths. They contain no raster images or font dependencies.
- Color logo and social SVGs are editable layouts with outlined typography and embedded PNG mascot artwork. The character remains raster. These are not fully vector mascot drawings.
- Mascot originals are 1254 × 1254 px. Exporting a layout at a larger size does not add detail to the character.
- App icons include full-square PNGs at 16, 32, 64, 128, 256, 512 and 1024 px. macOS variants have a rounded tile inset on a transparent 1024 px canvas. The neck meets the tile boundary.
- Toolbar PNGs include 16, 18, 20, 24 and 32 pt sizes at 1x, 2x and 3x in black and white. The PDF template is vector, 18 × 18 pt, with transparent counters.

## Native macOS integration

`app-icons/Paca.icon` is the current app icon source. It contains a transparent
alpaca foreground over a deeper lavender automatic gradient, based on `#A083DC`.
The mascot outline was recolored to satin black with built-in imagegen; the edit
prompt is saved in `sources/satin-outline-prompt.txt`, and the original remains in
`originals/paca-mascot-transparent.png`. Icon Composer supplies the tile highlights
and a neutral foreground shadow. Specular highlights on the alpaca group are off
so its black outline has a subdued finish. Dark, clear and tinted appearances are
rendered by Apple from that source. The mascot stays opaque in the default look.

Open this document in Icon Composer to edit it. Run `scripts/render-app-icon.sh`
from the project root to render all six appearances and 32/64 pt previews. These
PNGs are previews, not replacements for the native layered asset catalog.

`scripts/build-app-icon.sh` uses Xcode 26+ to compile `Assets.car`, `Paca.icns`,
and `icon-info.plist` into `.build/app-icon`. `scripts/install.sh` includes the
catalog and ICNS fallback in the signed app and declares `CFBundleIconName=Paca`.
`scripts/sync-brand.sh` updates the static app resource and PNG exports using the
compiler's ICNS fallback. These commands stop before replacing existing app assets
when the compiler is unavailable. Set `DEVELOPER_DIR` for a custom Xcode location.

For an Xcode app target, add `Paca.icon` directly to the target and set the app icon
name to `Paca`. Keep the `.icon` document outside the `.xcassets` catalog. Copy
`PacaTemplate.imageset` into an asset catalog for the menu bar. It declares template
rendering intent and preserves vector representation. Use it as an 18 pt menu bar image.

```swift
let image = NSImage(named: "PacaTemplate")
image?.isTemplate = true
image?.size = NSSize(width: 18, height: 18)
statusItem.button?.image = image
statusItem.button?.setAccessibilityLabel("Paca agent status")
```

Standalone SwiftPM executable builds do not pick up a native app icon automatically
and use the bundled ICNS fallback. Installed builds must leave
`NSApp.applicationIconImage` unset so macOS can render the native layers.

For menu bar status, keep the template icon neutral and use adjacent counts or a badge plus an accessible label. Do not depend on color alone. macOS handles template tint in light and dark menu bars.

## Web integration

Copy the `web/` files into your public asset directory and use relative URLs appropriate to your site. The manifest's PNG icons have purpose `any`; they are not Android maskable icons.

```html
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="icon" href="/favicon.ico" sizes="16x16 32x32 48x48">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/site.webmanifest">
```

## Typography and fonts

Manrope is the brand typeface. Use weight 800 for the wordmark, 600 for headings and 400 for body copy. IBM Plex Mono is for technical labels and examples. The native macOS app can keep system fonts for controls and terminals.

The original font files and SIL Open Font License texts are included in `fonts/`. Static Manrope instances and WOFF2 exports were generated from the supplied variable font. Source URLs are recorded in `sources/provenance.json`.

## Rebuild

The illustration sources are already included; normal rebuilds do not call an image generation service. Use Python 3.11+ and Node.js 20+.

```sh
python3 -m venv .venv-brand
.venv-brand/bin/pip install -r brand/scripts/requirements.txt
npm install --prefix brand/scripts
.venv-brand/bin/python brand/scripts/prepare.py
node brand/scripts/build.mjs
.venv-brand/bin/python brand/scripts/guide.py
.venv-brand/bin/python brand/scripts/validate.py
```

The `.icns` export requires macOS `iconutil`. The other outputs use bundled source artwork, fonts, SVG layouts, Sharp and ReportLab. Rebuilding replaces generated kit exports, never files under `Sources/`.

The commands above rebuild the original static brand kit. The native `.icon` source
and its previews use the separate project scripts described above. The original
`paca-brand-kit.zip` remains the version 1.0 archive.

## Artwork provenance

The color mascot and peeking variants were generated with the built-in imagegen tool and refined in this chat. Original PNGs are preserved in `originals/`; generation prompts are in `sources/`. The toolbar symbol is a separate native vector drawing. Wordmark outlines derive from Manrope ExtraBold. No Herdr or Capy artwork is included.
