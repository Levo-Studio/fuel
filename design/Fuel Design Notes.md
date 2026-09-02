# Fuel Design Notes

The written half of the design export. `Screens2c.dc.html` is the drawn half —
every one of the seventeen screens, in light and dark, at 390×844. This file
carries what a static render cannot: the rules behind the screens, the values
the prototype computes rather than draws, and the German-to-English copy table.

**Where the two disagree, the HTML wins for pixel values** — it is what was
actually drawn. These notes win for behaviour, because behaviour is not a pixel.

## Where this came from

The design lives in Claude Design (project `19fcd463-c5c8-4d6d-989c-1d4dcdf5bc33`)
and is pulled into this folder over the design MCP. **`design/` is read-only.**
If the code and the design disagree, the code is wrong. If you believe the design
itself is wrong, that is a question for the owner, not an edit you make here.

The project also holds two files this export deliberately omits:

- `Kalorien App 2c.dc.html` — the interactive prototype. Everything in these
  notes was read out of it. It is not exported because a running prototype
  invites reading behaviour out of placeholder data (`RECENTS`, seeded
  `entries`, the fake `estimate()` arithmetic) that is scaffolding, not spec.
- `Kalorien App Richtungen.dc.html` — five explored directions, four of them
  rejected. **Direction 2c is the one being built.** Nothing else is.

## Palette

Both themes, verbatim. `--cam` is the camera surface and stays dark in both —
Settings says so out loud (`Kamera bleibt in beiden Modi dunkel`).

| Token | Dark | Light |
|---|---|---|
| `bg` | `#111213` | `#faf9f8` |
| `surface` | `#1a1b1d` | `#ffffff` |
| `ink` | `#fafafa` | `#121212` |
| `muted` | `rgba(250,250,250,.45)` | `rgba(18,18,18,.45)` |
| `hair` | `rgba(250,250,250,.14)` | `rgba(18,18,18,.12)` |
| `hair2` | `rgba(250,250,250,.3)` | `rgba(18,18,18,.25)` |
| `hairSoft` | `rgba(250,250,250,.07)` | `rgba(18,18,18,.07)` |
| `soft` | `rgba(250,250,250,.12)` | `rgba(18,18,18,.09)` |
| `cam` | `#090a0a` | `#0d0d0e` |

There is no system-follows-the-OS option drawn. Settings offers exactly **Light**
and **Dark**, as a two-segment control.

## Accents

Five, in this order, `mono` first and default. The accent drives the ring, the
macro bars, filled buttons, and selection. Each carries its own on-colour.

| Key | Name (de → en) | Dark | Dark on | Light | Light on |
|---|---|---|---|---|---|
| `mono` | Mono → Mono | `#fafafa` | `#111213` | `#121212` | `#faf9f8` |
| `blau` | Blau → Blue | `oklch(0.72 0.13 250)` | `#0a1220` | `oklch(0.52 0.15 256)` | `#ffffff` |
| `gruen` | Grün → Green | `oklch(0.76 0.13 160)` | `#06140e` | `oklch(0.52 0.13 160)` | `#ffffff` |
| `sand` | Sand → Sand | `oklch(0.82 0.11 72)` | `#1a1206` | `oklch(0.58 0.12 62)` | `#ffffff` |
| `flieder` | Flieder → Lilac | `oklch(0.76 0.12 300)` | `#150a1c` | `oklch(0.53 0.15 300)` | `#ffffff` |

The error colour is a sixth value and is not an accent: `oklch(0.62 0.17 25)`,
used for the failed-key note in Settings.

The swatch in Settings is a 26px dot inside a 38px ring; the selected ring is
`0 0 0 1.5px ink`, the others `0 0 0 1px hair`.

## Type

Two families, both variable-weight Google fonts, both bundled — the app does not
reach the network for a typeface.

- **Plus Jakarta Sans** 400 / 500 / 600 / 700 — all prose, labels, buttons.
- **DM Mono** 400 / 500 — every number, every timestamp, every uppercase
  letter-spaced eyebrow.

The split is not decorative: a figure that changes as you log belongs to the
mono face so the layout does not shift under it. Sizes carry fractional values
(`11.5px`, `13.5px`, `14.5px`) — transfer them as written, they are design
points, not rounding artefacts.

Radii are `100px` (pills), `50%` (circles) and `16px` (the macro cards on
onboarding) — plus `22px` on the result screen's photo thumbnail. The 46px on
the outer frame is the phone mockup's own corner and never reaches the code.

## The meal label — read this before touching the nutrition core

**The label is derived from the course of the day, not from the clock alone.**
Breakfast, lunch and dinner are each assigned **once per day**, the first time an
entry falls inside that meal's window. Any further entry that arrives after one
of them but before the next main-meal window has been reached is a **Snack** —
breakfast is set but it is not yet lunchtime, or lunch is set and it is not yet
evening. Everything after dinner is a Snack too.

The main-meal windows:

| Label (de → en) | Window |
|---|---|
| Frühstück → Breakfast | `04:00 – 10:59` |
| Mittagessen → Lunch | `11:00 – 14:59` |
| Abendessen → Dinner | `18:00 – 22:59` |

Snack has no window of its own. It is what an entry gets when no main meal is
still available to it. Two consequences worth stating, because they are the
whole point of the rule:

- A **second** entry inside the breakfast window is a Snack, not a second
  breakfast — breakfast was already handed out.
- An entry at `16:00` on a day with **no lunch yet** is *lunch*, because the
  lunch window has passed unused and dinner has not been reached. A fixed
  `15:00–17:59` Snack band would get this wrong; this rule is why the design
  does not use one.

The user can overwrite the label on the result screen; the control cycles
forward through Breakfast → Lunch → Snack → Dinner and wraps. An overwritten
label is the user's, and re-deriving it later would undo their correction.

The day list groups in the order Breakfast, Lunch, Snack, Dinner — not
chronologically — and within a group the entries sort by time. A group with no
entries is not rendered at all.

### Two things in the export that are not the rule

- **Settings draws four rows with clock ranges**, Snack among them at
  `15:00 – 17:59`. Those rows are *drawn as shown* — they are the plain-language
  summary the user reads, and the Snack row names the ordinary gap between lunch
  and dinner. They are not the algorithm, and no code reads a Snack window.
- **The prototype's `labelFor(hour)` is a stub.** It maps an hour straight to a
  label with a fixed Snack band, because a click-through prototype has no day
  history to reason about. It is scaffolding for the demo, not the spec. The
  written rule above is the spec.

## Numbers the render cannot show

- **Goal defaults** — 2400 kcal, 160 g protein, 240 g carbs, 70 g fat.
- **Ring** — 120 viewBox, r 54, stroke 7, `stroke-linecap: round`, rotated −90°.
  Circumference is `339.3`; the offset is `339.3 × (1 − min(1, total ÷ goal))`.
  Rendered at 104×104. The percentage sits centred in 17px mono.
- **Macro bars** — 4px tall, `soft` track, `accent` fill, capped at 100%. In
  goal mode the value reads `used/goal`; in count-only mode it reads `N g` and
  the ring is not drawn at all.
- **Count-only mode** — the big total loses its `/ 2400 kcal` suffix and reads
  `kcal geloggt` (→ `kcal logged`) instead.
- **Result stepper** — ±10 kcal per tap, floored at 0.
- **Key test steps** — four, in order: `Verbindung aufbauen`, `Testdaten senden`,
  `Antwort erhalten`, `Modell bereit` (→ `Opening connection`, `Sending test
  request`, `Response received`, `Model ready`). Each row is a 20px slot: a check
  when done, a 2px spinner ring when active, a 6px dot when pending.
- **Analysis steps** — four, in order: `Analysiere Mahlzeit …`, `Erkenne
  Zutaten …`, `Schätze Mengen …`, `Berechne Nährwerte …` (→ `Analysing meal …`,
  `Identifying ingredients …`, `Estimating amounts …`, `Calculating nutrition …`).
  The progress bar is 120×2 and fills in quarters. These are the four Analysis
  screens 08–11 — one per step, not four different designs.
- **Provider labels** — `Modell: Claude Sonnet 5` and `Modell: Mistral Large`.
- **Key placeholders** — `sk-ant-…` and `mist-…`. These are placeholder strings
  from the design, not validation rules. Anthropic keys do begin `sk-ant-`;
  Mistral publishes no key prefix, so a prefix check there would reject valid
  keys. Check Mistral keys for shape only, and let the test call decide.
- **Recognised items** carry a confidence line: `sicher · ca. 150 g` /
  `unsicher · ca. 90 g` (→ `confident · approx. 150 g` / `unsure · approx. 90 g`).
  The list heading is `Erkannt` after a photo and `Aufgeschlüsselt` after text
  (→ `Recognised` / `Broken down`).

## Copy

Only the words change. Geometry, weight, letter-spacing, casing, opacity and
colour do not.

| German | English |
|---|---|
| Schritt 1 von 2 / Schritt 2 von 2 | Step 1 of 2 / Step 2 of 2 |
| Dein Modell, dein Key. | Your model, your key. |
| Die Schätzung läuft über deinen eigenen Zugang. Der Key bleibt auf dem Gerät. | The estimate runs on your own access. The key stays on the device. |
| API-Key | API key |
| Später in den Einstellungen änderbar. | Changeable later in Settings. |
| Weiter | Continue |
| Mit Ziel oder ohne. | With a goal, or without. |
| Kalorienziel festlegen | Set a calorie goal |
| Einfach nur zählen / Nur die Summe des Tages | Just count / The day's total, nothing else |
| Lokal. Kein Account. | Local. No account. |
| Heute | Today |
| Protein / Carbs / Fett | Protein / Carbs / Fat |
| ✕ Abbrechen / ‹ Zurück / Fertig | ✕ Cancel / ‹ Back / Done |
| Kamera / Text / Recent | Camera / Text / Recent |
| Beschreib die Mahlzeit | Describe the meal |
| Je genauer die Mengen, desto genauer die Schätzung. | The more exact the amounts, the more exact the estimate. |
| Analysieren | Analyse |
| Zuletzt gegessen | Recently eaten |
| Tippen loggt direkt — Label wird aus der Uhrzeit gesetzt. | Tapping logs it straight away — the label comes from the time. |
| ABBRECHEN | CANCEL |
| Neu / Hinzufügen | Discard / Add |
| ☆ Favorit / ★ Favorit | ☆ Favourite / ★ Favourite |
| Einstellungen | Settings |
| KI-Modell | AI model |
| Neu prüfen | Re-check |
| ✓ Verbindung steht | ✓ Connection works |
| Key nicht akzeptiert | Key not accepted |
| Key wurde nicht akzeptiert. | Key was not accepted. |
| Verbindung wird geprüft. / Alles bereit. | Checking the connection. / All set. |
| Key ändern | Change key |
| Darstellung / Light / Dark | Appearance / Light / Dark |
| Kamera bleibt in beiden Modi dunkel. | The camera stays dark in both. |
| Akzentfarbe | Accent colour |
| Zählweise / Mit Ziel / Nur zählen | Counting / With a goal / Count only |
| Kalorien | Calories |
| Automatische Labels | Automatic labels |
| Einträge werden nach Uhrzeit einsortiert. Im Ergebnis-Screen jederzeit überschreibbar. | Entries are filed by time of day. Always overridable on the result screen. |
| Alle Daten liegen auf diesem Gerät. Kein Account, keine Sync. Shortcut „Scannen“ öffnet direkt die Kamera. | All data lives on this device. No account, no sync. The "Scan" shortcut opens the camera directly. |

## The seventeen screens

Captions are the export's own, translated.

```
01  API key · model and key            10  Analysis · state 3
02  Key test runs automatically        11  Analysis · state 4
03  Key test passed                    12  Log · text entry
04  Onboarding · goal or count only    13  Log · recent meals
05  Today · goal mode, auto labels     14  Result after photo scan
06  Today · count-only mode, no ring   15  Result after text entry
07  Log · camera (default)             16  Settings · model, theme, accent
08  Analysis · state 1                 17  Settings · counting, goals, labels
09  Analysis · state 2
```

There is **no search screen**. A manual food search was considered and cut: the
log flow has three tabs — Camera, Text, Recent — and the tab bar draws three.
Do not add a fourth because a list screen would be easy.

The key screens (01–03) come *before* onboarding (04) and there is no skip
control drawn on any of them. Fuel asks for a key at first launch.
