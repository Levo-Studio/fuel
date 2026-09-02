# CLAUDE.md — Working instructions for Fuel

This file describes **Fuel** and nothing else. No infrastructure, no servers, no
deployment, no other projects. What is written here applies to work in this
repository.

## Read first

Three files in the repo apply alongside this one. Read them before touching
anything:

- `CONTRIBUTING.md` — the same content as here, in full prose and written for
  humans. In case of doubt, what it says wins.
- `README.md` — what Fuel is, how BYOK works, and how it is built.
- `LICENSE` — source-available, **no distribution**. Stricter than it looks at
  first glance. Read it before you suggest anything involving TestFlight,
  sideloading or a store.

And one folder: **`design/`** — the design export. See "Design fidelity" below.
It is the first thing you read and the last thing you check, and it is never
edited.

## Language

**Everything in this repository is English.** App interface, string catalog,
code, comments, commit messages, branch names, documentation, issues, pull
requests. Like its sibling Loop, and unlike Score, there is no German in Fuel —
not even in a comment.

The design export is written in German. **The labels are translated
(`Frühstück` → `Breakfast`, `Nur zählen` → `Count only`, `Schritt 1 von 2` →
`Step 1 of 2`). Only the words change. Geometry, weight, letter-spacing, casing,
opacity and colour do not.**

## What Fuel is

Fuel is a calorie tracker for iOS 26, written in SwiftUI with SwiftData for
local persistence. You set a daily goal or decide to only count, and then log
what you ate by photo, by typing a sentence, or by picking something you have
eaten before. Everything lives on the device: **no account, no cloud, no
CloudKit, no sync, no backend of any kind.** That is not a roadmap item that has
not happened yet. It is the product.

The estimation is done by a language model, and the model is **yours**. See
"BYOK" below.

## Design fidelity — the hard rule

`design/` holds the design export, committed here so that every writer and every
reviewer reads the same bytes:

- `Screens2c.dc.html` — **the file with the pixels in it.** All seventeen
  screens, light and dark, at 390×844.
- `Kalorien App 2c Screens.dc.html` — the wrapper that sets the colour tokens
  per theme and imports the screens four times (dark/mono, light/mono,
  dark/blue, light/green). Reading only the wrapper tells you the palette and
  nothing about a single screen.
- `Fuel Design Notes.md` — the written spec: the rules behind the screens, the
  values a static render cannot show, and the German-to-English copy table.
- `support.js` — the generic dc-runtime. It contains no design information. Do
  not spend a token on it.

**Every writer and every reviewer reads `design/` before the first line of code
or the first line of a review. No exceptions, including for a one-line change.**

- **`design/` is read-only.** It is never edited to match the code. If the code
  and the design disagree, the code is wrong. If you think the design itself is
  wrong, that is a question for the owner.
- Where the HTML and the notes disagree, **the HTML wins for pixel values** — it
  is what was actually drawn — and **the notes win for behaviour**, because
  behaviour is not a pixel. The meal-label rule is the live example of the
  second case; the notes say why.
- No colour, size, spacing, radius, opacity, letter-spacing or line-height is
  invented, rounded, or implemented "close enough". The HTML sizes are design
  points and transfer 1:1 to SwiftUI points.
- If a value you need is not in the export, that is a question for the owner,
  not a gap you fill with taste.
- **A reviewer who waves through a deviation from the design has not done the
  job.** The deviation is the thing the review is for.

The export is a snapshot. The owner refreshes it before a feature starts, and
the refresh lands as its own commit, so a design change is visible as a diff
rather than appearing silently inside a feature.

### The seventeen screens

Captions are the export's own, translated. Anything not on this list has no
design and therefore is not built:

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

There is **no search screen.** A manual food-search mode was considered and cut:
Fuel has three log modes — camera, text, recent — and the README says three. Do
not add a fourth because a list screen would be easy.

### Two decisions worth stating up front

Both were settled by the owner. Neither is reopened by an agent.

- **The key setup is part of onboarding and cannot be skipped.** Screens 01–03
  come before screen 04, exactly as drawn. Fuel asks for a key at first launch.
  The disabled states for camera and text entry still exist and still matter —
  a key can be removed or go invalid later in Settings — but there is no "skip
  for now" button, because there is none in the design.
- **The `Snack` label is derived from the course of the day, not from the clock
  alone.** Breakfast, lunch and dinner are each assigned once per day, the first
  time an entry falls into that meal's window; anything that arrives after one
  of them but before the next main-meal window is a snack, and so is everything
  after dinner. `Fuel Design Notes.md` has the full rule, the two consequences
  that make it worth the trouble, and the two things in the export that look
  like the rule and are not — Settings' four clock rows, and the prototype's
  `labelFor(hour)` stub. Read it before writing the nutrition core.

### Palette, for orientation only

Read the real values out of `design/`. This is here so a wrong file is obvious
at a glance.

```
dark    bg #111213   surface #1a1b1d   ink #fafafa   camera #090a0a
light   bg #faf9f8   surface #ffffff   ink #121212   camera #0d0d0e
accent  mono is the default (ink on bg); blue, green, sand, lilac as oklch
type    Plus Jakarta Sans 300/400/500/600, DM Mono 400
radii   100px (pills), 50% (circles), 16px (cards), 22px (result thumbnail)
```

The 46px radius in the export is the phone mockup's own corner. It is not an
app value and never reaches the code.

## BYOK — not negotiable

Fuel uses AI **exclusively** with a key the user brings.

- **No Levo Studio backend. No proxy. No fallback.** There is no server-side
  component of Fuel, and there is no "if the user has no key, route it through
  us" path. Not as a convenience, not behind a feature flag, not temporarily.
- **No Levo Studio key ships in the binary.** Not in source, not in an
  `xcconfig`, not in an `Info.plist`, not base64-encoded in a comment.
- Requests go **straight from the device** to `api.anthropic.com` or to
  Mistral's endpoint. Levo Studio never sees a request and could not read one if
  it wanted to.
- The user stays anonymous. There is no account with Levo Studio, only a key
  they fetched themselves from Anthropic or Mistral.

Concretely, for anyone touching AI code:

- **Keys live in the Keychain, never in `UserDefaults`.**
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, and iCloud Keychain sync is
  off — a synced key would travel through Apple's cloud, which is exactly what
  local-first is meant to avoid. One entry per provider, so a user can hold both
  keys and switch without losing the other.
- **Nothing is ever logged.** Not the key, not a prefix of the key, not the
  photo, not the text the user typed, not the model's reply. No `print`, no
  `os_log`, no temporary file on disk. The only place a meal's content is
  written down is its SwiftData entry.
- A new key gets a **format check first** (Anthropic keys begin `sk-ant-`;
  confirm Mistral's current format from Mistral's own documentation rather than
  guessing), and only then a single smallest-possible test call, so an obvious
  typo never costs an API request. The result is shown immediately, not
  discovered at the first photo scan.
- Images are **compressed on the device before upload.** The user is paying for
  those tokens.
- Error states are the ones in the design: `401` invalid key, `429` or
  `insufficient_quota` no credit with a link to that provider's billing page,
  network failure a plain retry. **No stack trace and no raw provider message
  reaches the interface.**

## Toolchain and commands

- **Xcode 26**, target **iOS 26.0**, **Swift 6** with
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: types are on the main actor
  unless they say otherwise. Anything that should not be — the calculation core,
  anything a test runs without a simulator — is explicitly `nonisolated`.
- Bundle ID `apps.levo-studio.Fuel`, matching its siblings.
- No linter, no formatter, no `.editorconfig`. Four spaces, no tabs,
  `// MARK: -` for structure, otherwise match the file you are editing.
- Synchronized folders: new files under `Fuel/` join the target on their own.
  **`Fuel.xcodeproj/project.pbxproj` is not touched for that.**

`xcode-select` points at the CommandLineTools on this machine, which cannot
build an iOS project. Prefix `DEVELOPER_DIR`:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Fuel.xcodeproj -scheme Fuel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

Testing is the same command with `test` in place of `build`.
`CODE_SIGNING_ALLOWED=NO` is deliberate: Fuel needs no entitlement and no
development team for a simulator build, so a clone builds without an Apple
Developer account.

`DEVELOPMENT_TEAM` is not stored in the project. It goes in `Local.xcconfig`,
which is gitignored; `Base.xcconfig` includes it optionally so a clone without
it still builds.

## Architecture rules — not negotiable

```
Fuel/
  Core/Design/     FuelPalette, FuelTypography, FuelMetrics, FuelMotion
  Core/Data/       the SwiftData store
  Core/Keychain/   the provider-key wrapper
  Core/AI/         provider clients, request and response shapes
  Models/          FoodEntry and friends — @Model types
  Nutrition/       pure calculation: totals, macros, the meal-label rule
  Features/        one folder per screen area: Onboarding, Today, LogFlow, Settings
  Resources/       fonts, Localizable.xcstrings
FuelTests/         Swift Testing
```

**The nutrition core knows no database.** `Fuel/Nutrition/` works on plain
`Sendable` values, not on `@Model` classes. Totals, macro splits and the meal
label are pure functions over pure values, which is what lets their tests run in
milliseconds without a `ModelContainer` and without a simulator. Nothing from
SwiftData travels deeper than the hand-off type.

**The nutrition core knows no view either.** No `@Observable`, no `Color`, no
`import SwiftUI`.

**Colour, size and motion come only from the design layer.** `FuelPalette`,
`FuelTypography`, `FuelMetrics`, `FuelMotion`. No numeric or colour literals in
feature files: no `.padding(17)`, no `Color(hex:)`, no hand-rolled
`timingCurve`. If a value is missing it goes into the design layer, not into the
call site. *Reduce Motion* is handled centrally in `FuelMotion` — at a hundred
call sites it would be forgotten at ninety of them.

**Everything the user can see is a string catalog key.**
`Fuel/Resources/Localizable.xcstrings`, maintained by hand
(`extractionState: manual`). No visible string sits as a literal in a view. The
interface is English-only — do not add a second language.

**There is no network code outside `Core/AI/`.** If a view is building a
`URLRequest`, the design of that feature is wrong.

## Code style

- **Four spaces**, no tabs.
- `// MARK: -` in any file with more than one type or a handful of functions.
- **No numeric or colour literals in feature files.** See above.
- **Nothing enforces style** — no SwiftLint, no SwiftFormat. Match the file you
  are editing.
- Never change formatting in the same commit as logic. If an indentation
  bothers you while reading: separate commit, or not at all.
- No `print`, no `debugPrint`, no commented-out code, no `TODO` without a name
  and a reason beside it. Preferably no `TODO` at all.

## Comments

Comments explain the **why**, not the what. A comment describing what the line
below it does is wasted. One explaining why it is not the obvious approach saves
the next person half a day. Whole paragraphs above a single constant are
deliberate here, not an exception.

**A comment that promises something the code does not do is worse than no
comment.** If you change behaviour, pull the comments above it along — including
the ones in neighbouring files repeating the same promise.

## Tests

`FuelTests/`, **Swift Testing** (`@Test`, `@Suite`, `#expect`) — not XCTest. A
red run is not delivered; a genuinely wrong test is fixed in its own commit,
with a reason.

The nutrition core is where the tests live, because it is pure and there is no
excuse: daily totals, macro arithmetic, the goal-versus-count-only split, and
above all the meal-label rule — first entry of the day, an entry between
breakfast and lunchtime, a second dinner, a day with nothing but snacks, an
entry the user relabelled by hand. Key-format validation is testable without a
network and is tested. Provider clients are tested against recorded response
shapes, never against a live endpoint.

Every fix ships with a test that fails **without** the fix. The counter-check is
mandatory: pull the fix, watch it go red, put it back, watch it go green. A
regression test nobody has seen fail is decoration.

## The agent workflow

Fuel is built with a writer/reviewer split, and the split is the point.

- One agent **writes** a feature in its own worktree
  (`git worktree add ../fuel-wt-<slug> feature/<slug>`).
- A **different** agent, with its own context, reviews the diff in that same
  worktree against `design/` and against this file. It does not write the fix.
- Before anything reaches `main`, a **main-gate** agent — independent again, and
  never the feature's reviewer — sees the full diff plus the resulting state of
  `main`, and checks: clean build, no avoidable warnings, no dead code, no
  leftover debug output, design fidelity a second time, formatting consistent
  with the repo, no AI attribution anywhere. For anything touching AI: no
  hard-coded key, no Levo Studio call path, Keychain rather than `UserDefaults`,
  and no logging of key, image or text.
- Findings go **back to the writer**, never into the reviewer's own hands. An
  agent that fixes what it just found has reviewed nothing.
- **Sub-agents never merge.** Only the owner merges to `main`, and deletes the
  branch and the worktree afterwards.

Features touching the same files are done **in sequence**, not in parallel. The
data layer is shared by onboarding, Today, the log flow and Settings; the
Keychain wrapper is shared by Settings and by both AI log modes. Two agents in
two worktrees editing the same file will silently overwrite each other and the
loser is whoever pushes second. **Check for file overlap before parallelising
anything.** Only genuinely disjoint work — the icon, the documentation — runs at
the same time.

## Commits

- Conventional Commits, description in **English**: `type(scope): description`.
  Scope optional but welcome.
- Types in use: `fix`, `feat`, `test`, `refactor`, `chore`, `design`, `docs`,
  `build`, `perf`, `security`, `revert`.
- The description says **what now holds**, not what was done. Anything
  non-obvious is justified in the body.
- **One commit = one logical change.** No collection commits, formatting never
  in the same commit as logic. Commit and push each small finished piece, not
  once at the end of a feature.
- **No tool trailers.** No `Co-Authored-By`, no "Generated with", no session
  IDs, no mention of AI tooling — not in commits, not in PR titles or bodies,
  not in code comments, not anywhere in the repo. This applies to every agent
  without exception.
- Rebase onto current `main` before a PR, unless another branch is based on your
  history — rebasing a base branch strands its dependents. Merges **to** `main`
  are `--no-ff`, with a body saying what landed and why.

## Branches

**Never commit directly to `main`** unless the owner says so explicitly.

Before every new branch: `git fetch --all --prune`, and if the base is behind
its remote, pull before branching.

Prefixes: `feat/`, `fix/`, `hotfix/`, `security/`, `refactor/`, `perf/`,
`design/`, `feedback/`, `ci/`, `deps/`, `migration/`, `docs/`, `test/`,
`chore/`, `spike/`, `release/`, `revert/`. Lowercase, hyphens, specific:
`feat/ai-provider-settings`, not `feat/settings`.

**No `claude/` prefix** and no other named after the tool that was used. The
branch is named after the work, not the hammer.

## How Claude is used here

Claude is a tool in this repository: code review, boilerplate, structure, a
second pair of eyes on a design spec. It is not a substitute for understanding.
**Every change is understood and answered for before it is merged** — if the
owner cannot explain what a line does and why it is there, it does not go in, no
matter which tool produced it. That is the difference between using a tool and
vibe-coding, and it is the reason the reviewer is never the writer.

Nothing in the repository mentions the tool. See "Commits".

## The repository is public

`github.com/levo-studio/fuel` is public **now**, not later. Every commit that
lands on `main` is visible to everyone from that moment. There is no phase of
"quick and dirty first, tidy up later" — every change on `main` has to look like
it was always there.

## License context

Fuel is source-available and follows Loop: read, clone, build, run on your own
devices. **No distribution** — no App Store, no TestFlight, no sideloading to
third parties, no sale, no handing a build to anyone else, and no presenting
yourself as the author or provider of Fuel. Copyright stays with Levo Studio.
Contributors keep authorship, grant Levo Studio the usage rights, and are named
in the credits.

Do not suggest a distribution path the license does not allow, and do not soften
the license text to make one fit.

## None of this happens without asking

Ask first, then touch:

- **`DEVELOPMENT_TEAM` and the bundle identifier** in `Fuel.xcodeproj`. Both
  hang off the owner's App Store access and never belong in a diff.
- **`Fuel.xcodeproj/project.pbxproj`** for anything but a deliberate
  build-setting change. Synchronized folders mean new files never need it.
- **Anything that would put a Fuel request on a Levo Studio server**, or a key
  anywhere but the Keychain. There is no version of this that gets approved, but
  ask anyway so the answer is on the record.
- **Anything in `design/`.** The export is read-only. Refreshing it is the
  owner's job and lands as its own commit.
- **Adding a dependency.** Fuel has none, and that is a feature.
- **A second AI provider** beyond Claude and Mistral.
- **Deleting user data paths** — anything that calls `ModelContext.delete` or
  throws a store away.
- **Push to `main`.** Work happens on a branch, merging is the owner's call.
