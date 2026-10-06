# Paca brand guidelines

## Identity

Paca is a native macOS client for Herdr. The name comes from alpaca. Use `Paca` in prose and `paca` in the supplied wordmark. The product descriptor is "A native macOS client for Herdr." The brand line is "A window into your herd."

The mascot should look curious and calm. Its upright ears, cream wool, lavender ear interiors and oat muzzle stay consistent. Preserve the face and proportions across materials.

## Logo system

Use the color mascot lockup for websites, introductory screens and promotional materials. Use the one-color symbol and wordmark for compact UI and one-color production. The standalone wordmark is useful when the mascot is already present elsewhere on the same layout.

Leave clear space of at least one-quarter of the symbol's height around logos. For a wordmark alone, leave half the lowercase x-height. These margins are outside the supplied artwork bounds.

- Color horizontal lockup: minimum 160 CSS px wide.
- Mono horizontal lockup: minimum 104 CSS px wide.
- Standalone wordmark: minimum 64 CSS px wide.
- Detailed mascot: minimum 48 CSS px high.
- Simplified symbol: 16 px minimum; 18 pt for the macOS menu bar; 20 or 24 px for toolbars.

Do not stretch, skew, outline the wordmark, rearrange letters or add glow. Keep the full ears in view. Use the cream logo on ink backgrounds; use ink on lavender, mint and paper.

## The window crop

In app icons and window illustrations, the alpaca's neck runs past the lower or side edge. The crop should look continuous, with no rounded base or gap beneath the neck. Keep the eyes, muzzle and ears inside the frame. The diagonal mint pose is the most playful variant; lavender is the default product icon; charcoal is the calmer alternate.

The transparent peeking asset already has an intentional bottom-right crop. Align both cropped edges with the container boundaries. Use `overflow: hidden` when composing it in a smaller window. Do not float the cropped character in open space. Use the complete mascot for free-standing placements.

## Color

| Name | Hex | Role |
| --- | --- | --- |
| Lavender | `#B8A2E8` | Primary brand field and selected details |
| Mint | `#CDE4D6` | Supporting field and curious mascot variant |
| Cream | `#FFF5DE` | Wool and light text on dark backgrounds |
| Oat | `#EAD2B2` | Muzzle and small warm accents |
| Ink | `#28262E` | Text, one-color marks and dark backgrounds |
| Paper | `#FAF8F4` | Light page backgrounds |
| Violet | `#69508F` | Links and primary controls on light backgrounds |

Use ink text on lavender, mint and cream. Their measured contrast ratios are 6.66:1, 11.13:1 and 13.77:1. Cream on ink is 13.77:1. Violet on paper is 6.30:1. White text on lavender is not suitable for normal-size body text.

The generated artwork contains subtle pixel variation. The hex values above define flat layout colors and code tokens; they are not claims that every raster pixel has an exact swatch value.

## Typography

Use Manrope 600 for brand headings and Manrope 400 for paragraphs. The wordmark uses supplied outlined Manrope 800 lettering. Use IBM Plex Mono 400 or 500 for short technical labels and code samples.

Suggested web scale: display 56-72 px, section heading 32-40 px, subheading 22-24 px, body 16-18 px, label 12-14 px. Body line height is 1.5. Keep lines around 55-75 characters. Sentence case is the default.

Keep SF Pro / the system font for native macOS UI. Keep the configured monospace font for terminal content. Do not replace platform text with the brand typeface merely to match the marketing pages.

## Interface color and status

Brand colors do not encode agent state. Use labels and distinct shapes with status colors. The optional token files include light and dark text-safe values for Working, Needs input, Done and Error. The native prototype's existing theme is separate.

Use an 8 px corner radius for small controls, 16 px for brand cards, and spacing on a 4 px grid. Large lavender or mint areas are for brand moments. Dense terminal views should keep neutral backgrounds.

## Voice

Write short, direct sentences. Name the agent or action when useful. Be friendly without baby talk. Avoid alpaca puns in errors, invented progress, or claims that Paca itself executes tasks that belong to Herdr or a connected agent.

Examples:

- Product description: "Paca brings your Herdr workspaces, agents and terminals into a native macOS app."
- Attention: "2 agents need input."
- Empty state: "No agents in this workspace."
- Disconnected: "Herdr is offline. Start Herdr to reconnect."
- Approval: "This agent needs approval. Open its terminal to respond."

The examples describe interface language, not a promise that every corresponding feature is implemented. Use the project README as the source for shipped capabilities.

## Export and source policy

Vector-only assets: toolbar symbol, template PDF, wordmark and mono lockups. Hybrid assets: color lockups and social SVGs with embedded PNG mascots and vector typography. Color character sources are 1254 px square. Use the included SVG layouts to edit composition, not as evidence that the mascot is vector.

The supplied menu bar PDF uses transparent eye and nose counters and is marked as a template in its image set. Let macOS choose its tint. Validate new glyph changes at actual 16-24 px size, not only enlarged.
