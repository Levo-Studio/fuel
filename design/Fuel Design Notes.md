# Fuel Design Notes

The written half of the design export. `Screens2c.dc.html` is the drawn half —
every one of the seventeen screens, in light and dark, at 390×844. This file
carries what a static render cannot: the rules behind the screens, the values
the prototype computes rather than draws, and the German-to-English copy table.

**Where the two disagree, the HTML wins for pixel values** — it is what was
actually drawn. These notes win for behaviour, because behaviour is not a pixel.

## What is here, and how to check a claim

**`design/` is read-only.** If the code and the design disagree, the code is
wrong. If you believe the design itself is wrong, that is a question for the
owner, not an edit you make here.

Three files carry design information, and they do not carry the same kind:

- **`Screens2c.dc.html`** — the seventeen screens as drawn. Every pixel value in
  the app comes from here, and every claim about a *drawn* value is greppable in
  it.
- **`Kalorien App 2c.dc.html`** — the interactive prototype. It holds the
  behaviour a still image cannot show: the accent table with each accent's
  on-colour, the step texts, the provider labels and key placeholders, the goal
  defaults, and the Settings copy that only appears once a control is used.
- **`Kalorien App 2c Screens.dc.html`** — the wrapper. Colour tokens per theme,
  and nothing else.

**Every claim below names which file backs it** — `[S]` for the screens, `[P]`
for the prototype, `[W]` for the wrapper. A reviewer grep that comes back empty
means you are grepping the wrong file, and a claim with no marker is a bug in
these notes.

The prototype ships with placeholder data — `RECENTS`, the seeded `entries`
list, the fake arithmetic in `estimate()`, the `labelFor(hour)` stub. **None of
that is spec.** It exists so the prototype can be clicked through.

One file from the design project is deliberately not exported:
`Kalorien App Richtungen.dc.html`, five explored directions with four rejected.
**Direction 2c is the one being built.** Nothing else is.

## Palette

Both themes, verbatim `[W]`. `--cam` is the camera surface and stays dark in
both. Settings carries a line saying so under the Light/Dark control `[P]` — it
is not drawn on screen 16, which goes straight from `Darstellung` to
`Akzentfarbe`, because the note only appears once the control is used.

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

Five `[P]`, in this order, `mono` first and default. The accent drives the ring,
the macro bars, filled buttons, and selection. Each carries its own on-colour.

Only four of the ten accent/theme pairs are realised in the screens — the
wrapper renders dark/mono, light/mono, dark/blue and light/green `[W]`, and
those four match this table exactly. The remaining on-colours are prototype
values and cannot be grepped in this folder.

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

- **Plus Jakarta Sans** 300 / 400 / 500 / 600 `[S]` — all prose, labels,
  buttons. Weight 300 is drawn exactly five times, for the `+` glyph on the
  Recent rows (`font:300 22px`). **There is no 700 anywhere in the screens**,
  even though the export's own Google Fonts import requests `wght@400;500;600;700`
  — the import is wrong in both directions: it asks for a weight nothing uses
  and omits the one that is drawn. Bundle 300 through 600.
- **DM Mono** 400 only `[S]` — every number, every timestamp, every uppercase
  letter-spaced eyebrow. No 500 is drawn, despite the same import requesting it.

The split is not decorative: a figure that changes as you log belongs to the
mono face so the layout does not shift under it. Sizes carry fractional values
(`11.5px`, `13.5px`, `14.5px`) — transfer them as written, they are design
points, not rounding artefacts.

Radii `[S]`, and there are no others: `100px` (pills, 21×), `50%` (circles,
26×), `16px` (the macro cards on onboarding, 3×) and `22px` (the result
screen's photo thumbnail, 1×). The `46px` that appears seventeen times is the
phone mockup's own corner — one per frame — and never reaches the code.

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
- **Macro bars are goal-mode only** `[S]`. Screen 05 draws three 4px bars —
  `soft` track, `accent` fill, capped at 100% — with the value as `used/goal` in
  11.5px mono. **Screen 06 draws no bars and no ring at all**: the three macros
  become a plain row of `font:400 22px 'DM Mono'` values under `font:500 11px`
  labels. Count-only mode is not goal mode with the ring hidden; it is a
  different layout, and building bars into it is a design deviation.
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
- **Provider labels** `[P]` — `Modell: Claude Sonnet 5` and `Modell: Mistral
  Large`. The screens draw only the Claude label, because Claude is the selected
  segment in every frame; the Mistral label appears when the segment is switched.
- **Key placeholders** `[P]` — `sk-ant-…` and `mist-…`. The screens draw the
  filled-in form `sk-ant-a1b2c3d4e5`. These are placeholder strings
  from the design, not validation rules. Anthropic keys do begin `sk-ant-`;
  Mistral publishes no key prefix, so a prefix check there would reject valid
  keys. Check Mistral keys for shape only, and let the test call decide.
- **Recognised items** carry a confidence line. After a photo it reads
  `sicher · ca. 150 g` / `unsicher · ca. 90 g` (→ `confident · approx. 150 g` /
  `unsure · approx. 90 g`); after text it reads `Menge erkannt` / `Menge
  geschätzt` (→ `Amount recognised` / `Amount estimated`), because a typed
  amount is either given or it is not.
  The list heading is `Erkannt` after a photo and `Aufgeschlüsselt` after text
  (→ `Recognised` / `Broken down`).

## Copy

Only the words change. Geometry, weight, letter-spacing, casing, opacity and
colour do not.

Rows marked `[P]` belong to states the screens do not draw — a failed key test,
the Settings note under Light/Dark, the shortcut sentence. They are spec; they
are simply not greppable in `Screens2c.dc.html`. Everything unmarked is drawn.

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
| Neu / Hinzufügen | New / Add |
| ☆ Favorit / ★ Favorit | ☆ Favourite / ★ Favourite |
| Einstellungen | Settings |
| KI-Modell | AI model |
| Neu prüfen | Re-check |
| ✓ Verbindung steht | ✓ Connection works |
| Key nicht akzeptiert `[P]` | Key not accepted |
| Key wurde nicht akzeptiert. `[P]` | Key was not accepted. |
| Verbindung wird geprüft. / Alles bereit. | Checking the connection. / All set. |
| Key ändern `[P]` | Change key |
| Darstellung / Light / Dark | Appearance / Light / Dark |
| Kamera bleibt in beiden Modi dunkel. `[P]` | The camera stays dark in both. |
| Akzentfarbe | Accent colour |
| Zählweise / Mit Ziel / Nur zählen | Counting / With a goal / Count only |
| Kalorien | Calories |
| Automatische Labels | Automatic labels |
| Einträge werden nach Uhrzeit einsortiert. Im Ergebnis-Screen jederzeit überschreibbar. `[P]` | Entries are filed by time of day. Always overridable on the result screen. |
| Alle Daten liegen auf diesem Gerät. Kein Account, keine Sync. | All data lives on this device. No account, no sync. |
| …Shortcut „Scannen“ öffnet direkt die Kamera. `[P]` | …The "Scan" shortcut opens the camera directly. |
| Foto-Eintrag / Text-Eintrag | Photo entry / Text entry |
| AUFGENOMMENES FOTO | CAPTURED PHOTO |
| Menge erkannt / Menge geschätzt | Amount recognised / Amount estimated |
| Erkannt / Aufgeschlüsselt | Recognised / Broken down |

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
