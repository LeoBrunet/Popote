# Popote: is it doable, and how?

> **Decisions on 2026-10-27**: week planning ✗, cook mode and Claude connector set aside. Yes to the smart shopping list → Bring! (reading what's already on the list to merge with it), and yes to the journal synced with Apple Health. Name confirmed: Popote. Logo and 5 styles to choose from in UIStudio. **App in English + French** (String Catalog `Localizable.xcstrings`, English as the source language, French translation; Ciqual has English names too, and Open Food Facts returns `product_name_fr`/`_en`). Bring! merge approach validated.

> **Built on 2026-10-27**: the iOS app is in this folder (see README.md). It covers import from all 4 sources, macros, groceries + Bring! sync, journal + Apple Health, pantry, EN/FR.

Written 2026-10-27. Screens: UIStudio → project "Popote" (`UIStudio/Screens/Popote/`).

## 1. Share a link → recipe + video + shopping list

**Doable: yes. Quality depends on the source.**

| Source | Embedded video | Getting the recipe | Expected quality |
|---|---|---|---|
| Recipe sites | – (photo) | `schema.org/Recipe` JSON-LD in the page (most sites: Marmiton, CuisineAZ, BBC Good Food…). Deterministic, free | ★★★★★ |
| YouTube | Official iframe player (`youtube.com/embed/ID?start=…`): steps can jump to the right moment | Data API `videos.list` → `snippet.description` (often holds the recipe). Spoken-only recipe → subtitles (no official API for videos you don't own; unofficial `timedtext` endpoint) | ★★★★ |
| TikTok | Official oEmbed (embed player) | The oEmbed `title` field holds the caption | ★★★ |
| Instagram | oEmbed, no token needed since 06/2026 (1,000 req/h) | ⚠️ Meta forbids using oEmbed data for anything other than display. Caption options: (a) in-app WKWebView logged in to the user's own account, reading the caption on device (personal use, grey area); (b) "paste the caption" in the share extension; (c) third-party scrapers (against ToS, avoid). Recipes that are only spoken in the video can't be extracted without downloading the video (forbidden) | ★★ to ★★★ |

**Pipeline**
1. **Share Extension** (`NSExtensionActivationSupportsWebURLWithMaxCount`, plus text): Popote appears in the share sheet of Instagram, YouTube, TikTok and Safari. The extension (limited to ~120 MB of memory) only stores the URL in an App Group and starts the import; a notification fires when it's done.
2. **Extractor per source** (see the table) → raw text (caption, description, subtitles, JSON-LD).
3. **Structuring**: text → `{title, servings, ingredients[{name, qty, unit}], steps[{text, timestamp}]}`.
   - Option A, **Apple Foundation Models** (on device, iOS 26, free, offline, `@Generable` = guaranteed structured output). Good enough for a caption or description; small context window (~4k tokens), so long subtitles need splitting into chunks.
   - Option B, **Claude API** (Haiku): more reliable on messy text, about 0.1–0.5 cents per recipe. But it's API billing, separate from your Pro plan.
   - Recommendation: JSON-LD first, then Foundation Models, with Claude API only as a fallback when confidence is low.
4. **"Check the import" screen**: every guessed quantity is highlighted (the user doesn't blindly trust the AI).

**Bring! export**
- No public API (confirmed). Bring!'s importer works in **pull** mode: it reads a public page containing `schema.org/Recipe` JSON-LD (the same mechanism their website widget and Mealie use).
  → Our backend publishes `https://<domain>/r/<id>` (minimal page with JSON-LD for the selected ingredients) and the app opens Bring!'s import link with that URL. Needs a public server (tiny one, can be the same as Coach's).
- Unofficial reverse-engineered REST API (`bring-api` on PyPI / `node-bring-api`): adds items directly, but you'd store your Bring! password and it can break at any time. Avoid.
- **100% official alternative: Apple Reminders** (EventKit). Since iOS 17 a "Groceries" list sorts items by aisle on its own. Zero backend.
- To verify at implementation time: the exact format of Bring!'s import deeplink (seen in widgets, not publicly documented).

**✅ Chosen option: read and write the Bring! list (unofficial API)**
- Login with your Bring! email + password → token (kept in the Keychain). An account created with Google/Apple first needs a password set in Bring!.
- `load_lists` → choose the list (e.g. "Maison", shared), `get_list` → current items (`name` + free-text `specification`, e.g. "2" or "400 ml").
- **Merge**: Popote's items are matched against Bring!'s. Bring! stores catalog names in German, translated per language (e.g. "Zitrone" shows as "Citron"), so download the catalog/translation file once and match on names + synonyms. Then three cases: missing → ADD; already there with a quantity → update `specification` (1 → 4); already there with no quantity → nothing to do.
- Send everything in one `batch_update` (ADD / update; never remove what Emma added).
- Can be done **on device, without a server** (direct HTTP calls to api.getbring.com). The quick reference is the `bring-api` Python package / `node-bring-api` to port to Swift.
- Risk: unofficial API, can break after a Bring! update. The import link stays as a fallback.

## 2. Calories and macros per ingredient + barcode scan

**Doable: yes, with good data in France and Europe.**
- **Generic ingredients**: **Ciqual** table (ANSES, free, ~3,200 foods, **French names**, which suits French recipes) + **USDA FoodData Central** (free API) as a fallback. Load Ciqual into the app (SQLite, a few MB): works offline and instantly.
- **Barcode**: VisionKit `DataScannerViewController` (native, very fast) → **Open Food Facts** API v2 `GET /api/v2/product/{ean}?fields=product_name,brands,nutriments,nutriscore_grade,serving_size`. Free, ODbL licence, excellent coverage in France and good in Sweden. Send a proper User-Agent, cache results, and check `status` (it returns HTTP 200 even when the product is missing).
- **Unknown product**: photo of the nutrition table → OCR (Vision `RecognizeTextRequest`) → structured, then optionally contributed back to OFF.
- **The hard part is matching, not the database**: "2 c. à soupe de miso" → which food? how many grams? → the LLM proposes the match plus a weight conversion (density/unit table: tablespoon of paste ≈ 18 g, average avocado ≈ 150 g…), and the user confirms. Show a **reliability score** for each recipe (verified / estimated / missing).
- Commercial alternatives (Nutritionix, FatSecret, Edamam): better US coverage, paid. Not needed for you.
- **✅ Apple Health sync (chosen)**: each meal in the journal = one `HKCorrelation(.food)` holding `dietaryEnergyConsumed`, `dietaryProtein`, `dietaryCarbohydrates`, `dietaryFatTotal` (+ fibre, sugars, sodium if known), with metadata (`HKMetadataKeyFoodType` = recipe name). Editing or deleting a meal → delete and rewrite the sample (keep its UUID). Reads: `activeEnergyBurned`, `basalEnergyBurned`, `bodyMass` → daily target = rest + active (+ planned session) ± goal. Coach and Bevel then see the meals.

## 3. Other ideas (in the mockups)

- **Cook mode**: one step at a time, screen kept on, video starting at the step's timestamp, timers as a Live Activity (lock screen), "next" by voice.
- **Week planning**: assign recipes to days, batch cooking (leftovers = 0 min), then generate the shopping list in one tap.
- **Smart list**: quantities from several recipes merged and units converted, sorted by aisle, pantry items removed automatically.
- **Pantry / fridge**: filled by ticked-off shopping items and scans, expiry dates, "what can I cook tonight?" from MY recipes.
- **Journal**: log a recipe portion in one tap, scans, photo of the plate (estimated, low precision).
- **Coach link** 💡: Popote reads the day's training (same server / MCP as Coach) and adjusts targets (interval day → more carbs, snack 1 h before).
- **Claude connector** (same model as Coach, "option B", Pro plan): MCP tools `list_recipes`, `get_pantry`, `add_recipe`, `plan_week`, so you can ask Claude "plan my week with high protein and what's in my fridge" with no API cost.
- Later: Siri / Shortcuts ("add to Popote"), recipe sharing between people, price estimate.

## Suggested architecture

- iOS: SwiftUI + Share Extension + App Group, SwiftData, CloudKit sync. On-device structuring (Foundation Models), Ciqual embedded.
- Small backend (Node, reusing Coach's): YouTube proxy (API key), public Bring! pages, MCP connector, Claude fallback.
- MVP in this order: Share → JSON-LD/YouTube → recipe + embed → Reminders export → Ciqual macros → OFF scan → Bring! → Instagram.
