# Recall design system

## Direction

Recall helps independent professionals keep a clear current plan while client conversations change it. The design metaphor is a living page: a stable record with visible, reviewable amendments. Current and proposed work remain distinct. The main navigation is Today, Projects and Sources, with a labeled Add update action.

Primary actions occupy a reserved safe bottom region, aligned with the same 860-unit maximum width as page content. They do not float over plan cards. Today counts all pending answers, with separate sections for your review and responses from someone else. Each navigation tab keeps its own scroll position. A saved recording is exported from its source details only after validating an existing file inside the app's owned audio folder; JSON backups do not carry audio files.

The visual identity and vector paths in this folder were drawn specifically for this rebuild. Familiar functional silhouettes remain recognizable; original composition, geometry and a consistent stroke family establish the identity. Original artwork is not a guarantee of legal uniqueness or trademark clearance.

## Reference studies

The parent task inspected these Mobbin screens. They inform general interaction principles; no reference imagery, layout or proprietary icon artwork is embedded in this product:

- [Asana project ownership](https://mobbin.com/screens/b20df089-35e5-455d-9e3d-86f122780bfa): keep the responsible person explicit.
- [Linear Mobile overview](https://mobbin.com/screens/2d1fdc3c-3758-46bb-88e1-5cfd39ce4148): restrained hierarchy and legible updates.
- [Jira dashboard](https://mobbin.com/screens/733f90a7-6308-467f-b24e-f0b1a38dd205): comparison showing why Recall should avoid a dense dashboard of equal-weight panels.

## Flora status and asset provenance

**Original vector interim; one Flora exploration completed and reviewed.** The parent connected Flora's official MCP endpoint at `https://agents.flora.ai/mcp`. A bounded authenticated run produced one 1024 × 1024 exploration using `mcp__flora__flora_create_generations`, model `t2i-flux-2-klein-4b`. The quote was 4 credits / $0.004 and the returned charge was $0.004; actual credits charged were not separately reported. Run: `run_m17c5qmyvtncstcdasv43qwvcs8gwgjy`.

The generated image is `assets/flora/recall-icon-exploration.png` and non-secret run metadata is in `assets/flora/generation-status.json`. Project sharing is restricted. Visual inspection found unwanted texture/shadows and weak fold geometry, so the clean original vector remains the recommended interim app icon. The functional vector family and current platform PNG exports must not be described as Flora-generated. No second generation was submitted. See `assets/brand/PROVENANCE.md`.

## Color and typography

| Role | Light value | Intended use |
|---|---|---|
| Paper | `#F6F2EA` | App background |
| Surface | `#FFFFFF` | Input and focused content |
| Ink | `#172E34` | Primary text |
| Muted | `#52666B` | Supporting text |
| Petrol | `#14535B` | Primary action |
| Coral | `#A43F2A` | Changed values, paired with text |
| Green | `#286544` | Confirmed status, paired with text |
| Amber | `#775216` | Pending status, paired with text |

Calculated contrast for exact solid pairings: ink/paper 12.74:1, muted/paper 5.42:1, white/petrol 8.68:1, coral/paper 5.66:1, green/white 6.92:1 and amber/paper 6.26:1. These values do not certify the complete application's contrast or accessibility.

Dark semantic surfaces and colors are supplied in `RecallPalette.dark`. Use `RecallPalette.of(context)` instead of light-only constants when styling state panels. Use `RecallTheme.light` and `.dark` on MaterialApp. Typography uses the platform/framework font family and script fallback, a restrained size scale, natural line height and slightly tightened large headings. Do not lock component heights around text.

## Components and APIs

```dart
import 'design/design.dart';

MaterialApp(theme: RecallTheme.light, darkTheme: RecallTheme.dark);
RecallIcon(RecallGlyph.projects, size: 24, color: palette.accent);
RecallBrand(size: 40, showWordmark: true);
final palette = RecallPalette.of(context);
```

The custom vector icon widget has no SVG dependency. The original 24-unit SVG masters are in `assets/icons`; the widget draws the matching restricted absolute path commands through CustomPainter. Directional back/right icons mirror in RTL. Other icon geometry remains unchanged. Pass `semanticLabel` only when the icon conveys meaning not already supplied by an enclosing button or label.

## State and interaction rules

- A request stays proposed until the required people confirm the same version.
- Pending edits never silently overwrite the current confirmed plan.
- Use explicit Current / Proposed labels and source access; color alone is insufficient.
- Distinguish recorded speech, machine transcription/OCR, translation and user recollection.
- Recipient views expose only selected project items and selected evidence.
- Confirmation, delivery, recipient acceptance and payment are different states.
- Offline edits show Saved on this device. Server-dependent confirmation remains pending.
- Preserve drafts on errors, permission denial, interruption and expired sessions.
- Essential numbers, dates and conditions wrap; do not hide them in truncated cards.

## Accessibility and internationalization

Use 48-unit action targets throughout, natural text reflow, meaningful labels and logical screen-reader order. Test VoiceOver and TalkBack, larger text, reduced motion, keyboard insets and small phones. Fields use locale-aware display while preserving canonical currency, date-only versus exact-time intent and original source wording. Material edits to a reviewed translation require another version review.

## Reproducing the visual review

Build and serve `build/web`, then run `node tool/visual_smoke.cjs` from the Flutter project with Playwright resolvable through Node or `NODE_PATH`. `RECALL_BASE_URL` overrides the default local preview URL and `RECALL_SCREENSHOTS_DIR` changes the output folder. The script enables Flutter semantics and uses a fresh example workspace. It captures 390 × 844 phone screens, light/dark settings, and 1365 × 1000 desktop screens, along with semantic text and a JSON error/capture manifest. Browser captures complement the narrow/large-text widget regressions; native screen readers and native device appearance need separate verification.

Do not encode interface text in artwork. Publish a tested language capability matrix instead of treating provider language counts as a quality promise. The theme and icon code are infrastructure; accessibility and real-language correctness require verification in the running app.

## Exported brand assets

- `assets/brand/icon-1024.png`: opaque square app-icon master.
- `assets/brand/adaptive-foreground.png`: transparent Android adaptive foreground.
- `assets/brand/adaptive-background.png`: opaque Android background.
- `assets/brand/monochrome.svg`: original monochrome vector.
- `assets/brand/ios/AppIcon.appiconset`: iPhone/iPad/marketing PNG sizes with Contents.json.
- `assets/brand/icon-family.png`: visual review contact sheet.

Platform generated catalogs are not modified by this design task. Exports were rasterized from the same controlled original vector geometry using a local deterministic renderer. Inspect masks, small sizes, tinted/dark behavior and platform-specific requirements before release. Asset presence is not store approval.
