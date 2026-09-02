# Contributing

Fuel is a calorie tracker for iOS 26: three ways to log a meal — a photo, a
sentence, or something you have eaten before — and a day screen that adds them
up. Everything lives on the device, and the AI runs on a key the user brings
themselves. No account, no backend, no sync.

Contributions are welcome across the whole thing: bug fixes, features, UI work,
refactorings, documentation, tests. If an animation feels too hectic to you, a
hit area too small, a label unclear — those are good PRs.

## Why I would like this to become more than a one-person app

Fuel exists because every tracker I tried wanted an account before it wanted my
lunch, and then made me search a food database for four minutes to log two eggs.
So I built the small one, where you point a camera at the plate and it is done.

Small is the point, and small is also the risk: a project like this very easily
stays a thing one person uses on one phone and nobody ever looks at again. A
food tracker gets used three times a day, and things used three times a day are
exactly where somebody else notices what I stopped seeing after the third week —
the button two points off, the empty state nobody hit before, the label that
made sense to me and to nobody else. I cannot review my own blind spots. That is
what other people are for.

## Read this before you start

Four things, in this order, and the first one is not optional:

1. **`design/`** — the design export. It is the source of truth for every value
   in the app. See "Design fidelity" below.
2. [`README.md`](README.md) — what Fuel is, how BYOK works, how it is built.
3. [`LICENSE`](LICENSE) — source-available, **no distribution**. Stricter than
   it looks. Read it before you suggest anything involving TestFlight,
   sideloading or a store.
4. [`CLAUDE.md`](CLAUDE.md) — the same rules as here, condensed for a tool that
   reads them. Where the two disagree, **this file wins**.

## Setup

You need **Xcode 26**. The project targets **iOS 26.0** and uses **Swift 6**
with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — types are bound to the main
actor by default, and anything that should not be is explicitly `nonisolated`.
The nutrition core is `nonisolated`, deliberately.

Clone it, open `Fuel.xcodeproj`, build. That is the whole setup: there are no
dependencies to fetch, no package resolution, no generated files.

From the command line, `xcode-select` points at the CommandLineTools on many
machines, and those cannot build an iOS project. Either switch it permanently or
prefix each call:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Fuel.xcodeproj -scheme Fuel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

### Working without your own developer team

You need **none**. Fuel has no entitlements, no capabilities and no container —
nothing hanging off an App Store account. `CODE_SIGNING_ALLOWED=NO` builds and
runs the whole app in the simulator, and no feature is missing without a
signature.

For a physical device you do need a team, and it does not go into the project:
copy `Local.xcconfig.example` to `Local.xcconfig` and put your Team ID there.
`Base.xcconfig` includes it optionally, so a clone without it still builds, and
`Local.xcconfig` is gitignored and cannot end up in a commit.

That also means `DEVELOPMENT_TEAM` and the bundle identifier
(`apps.levo-studio.Fuel`) never belong in a diff. If Xcode writes them into
`Fuel.xcodeproj` behind your back — it does that — take them back out before you
push.

### You need your own API key to work on the AI parts

There is no shared key, no test key and no Levo Studio key anywhere in this
repository, and there will not be one. Get a key from Anthropic or Mistral for
your own testing. It goes in the app at runtime, into the Keychain, and nowhere
near a file you can commit.

Provider clients are tested against **recorded response shapes**, never against
a live endpoint. A test suite that costs money to run is a test suite nobody
runs.

## Project structure

```
Fuel/
  Core/Design/     FuelPalette, FuelTypography, FuelMetrics, FuelMotion
  Core/Data/       the SwiftData store
  Core/Keychain/   the provider-key wrapper
  Core/AI/         provider clients, request and response shapes
  Models/          FoodEntry and friends — @Model types
  Nutrition/       pure calculation: totals, macros, the meal-label rule
  Features/        Onboarding, Today, LogFlow, Settings
  Resources/       fonts, Localizable.xcstrings
FuelTests/         Swift Testing
design/            the design export — read-only
```

**`Fuel/Nutrition/`** is the calculation core, and it knows neither the database
nor a view. Plain `Sendable` values and pure functions over them — no `@Model`
class travels in here, and no `@Observable`, no `Color`, no `import SwiftUI`
either. That is what makes it testable in milliseconds without a
`ModelContainer` and without a simulator, and it stays that way. Nothing from
SwiftData goes deeper than the hand-off type.

**`Fuel/Core/Design/`** is the only source for colour, size and motion.
`FuelPalette` resolves every token for light and dark and all five accents,
`FuelMetrics` holds spacings and radii, `FuelTypography` the type scale,
`FuelMotion` the curves — including the central handling of *Reduce Motion*. A
value that is missing goes in here, not into the call site.

**`Fuel/Core/AI/`** holds the provider clients and the request and response
shapes. **There is no network code anywhere else.** If a view is building a
`URLRequest`, the design of that feature is wrong.

**`Fuel/Core/Keychain/`** is the only place a key is read or written. One entry
per provider, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, iCloud Keychain
sync off. Never `UserDefaults`, not even temporarily, not even in a branch you
are going to clean up.

**`Fuel/Resources/`** holds the fonts and `Localizable.xcstrings`. Every visible
string lives in the catalog, which is maintained by hand
(`extractionState: manual`). No visible string sits as a literal in a view, and
there is no second language.

**`FuelTests/`** is Swift Testing. **`design/`** is read-only — see below.

The project uses synchronized folders: new files under `Fuel/` and `FuelTests/`
join the target on their own. `Fuel.xcodeproj/project.pbxproj` does not have to
be touched for that, and a diff that touches it without a build-setting reason
is a mistake.

## Design fidelity

This is the rule people break first, so it gets its own section.

**`design/` is the source of truth for every colour, size, spacing value, radius,
opacity, letter-spacing, line-height and state.** Not a mood board, not a
starting point. The export contains `Fuel Design Notes.md` — the written spec —
and `Screens2c.dc.html` with all seventeen screens in light and dark at 390×844.
The HTML sizes are design points and transfer 1:1 to SwiftUI points.

Read it before the first line of code. Yes, also for a one-line change.

- Nothing is invented, rounded, or implemented "close enough". The sizes carry
  fractional values — `11.5px`, `13.5px`, `14.5px` — and those are design
  points, not rounding artefacts. Transfer them as written.
- **If a value you need is not in the export, that is a question, not a gap to
  fill with taste.** Ask. I would much rather answer an email than review a
  screen built on a guess.
- `design/` is never edited to match the code. **If the code and the design
  disagree, the code is wrong.** If you think the design is wrong, that is a
  question for me, not an edit you make in `design/`.
- Where the HTML and the notes disagree, **the HTML wins for pixel values** —
  it is what was actually drawn — and **the notes win for behaviour**, because
  behaviour is not a pixel.

Four facts about the export, so nobody rediscovers them the hard way:

- **The seventeen screens are the whole app.** Anything not on that list has no
  design and is therefore not built. In particular there is **no search
  screen**: the log flow has three tabs and the tab bar draws three. Do not add
  a fourth because a list screen would be easy.
- **The meal label is not a clock lookup.** Breakfast, lunch and dinner are
  handed out once per day, the first time an entry falls into that meal's
  window; everything else is a snack. `Fuel Design Notes.md` has the rule, the
  two consequences that make it worth the trouble, and the two things in the
  export that look like the rule and are not — Settings' four clock rows, and
  the prototype's `labelFor(hour)` stub. Read that section before you touch the
  nutrition core.
- **Count-only mode is not goal mode with the ring hidden.** It is a different
  layout: no ring, no macro bars, the macros as a plain row of numbers. Building
  bars into it is a design deviation, not a shortcut.
- **The prototype's data is not spec.** `RECENTS`, the seeded entries, the fake
  arithmetic in `estimate()` — scaffolding so the prototype can be clicked
  through. And the `46px` radius that appears seventeen times is the phone
  mockup's own corner. It never reaches the code.

The export was written in German. The labels are translated to English —
`Frühstück` → `Breakfast`, `Nur zählen` → `Count only`, `Schritt 1 von 2` →
`Step 1 of 2`; the full table is in the notes. **Only the words change.**
Geometry, weight, letter-spacing, casing, opacity and colour do not move because
the English word is longer.

## Rules the app is built on, which a PR does not get to relax

Three of them, and they are settled. You are very welcome to argue with me by
email; you are not welcome to argue with me by pull request.

**1. BYOK, with no fallback.** There is no Levo Studio backend, no proxy, no "if
the user has no key, route it through us" path — not as a convenience, not
behind a feature flag, not temporarily. No Levo Studio key ships in the binary,
not in source, not in an `xcconfig`, not in an `Info.plist`, not base64-encoded
in a comment. Requests go straight from the device to the user's provider.

**2. Nothing is ever logged.** Not the key, not a prefix of the key, not the
photo, not the text the user typed, not the model's reply. No `print`, no
`os_log`, no temporary file on disk. The only place a meal's content is written
down is its SwiftData entry. This one bites during debugging, which is exactly
when it matters — take the `print` back out before you commit, not after I ask.

**3. Local only.** No account, no cloud, no CloudKit, no sync, no analytics, no
crash reporter. There is nothing to sync, so there is nothing to leak, and that
is the feature.

Error states are the ones in the design: `401` invalid key, `429` or
`insufficient_quota` no credit with a link to that provider's billing page,
network failure a plain retry. **No stack trace and no raw provider message
reaches the interface.**

## How a change happens

**Larger feature or restructuring:** open an issue first, then build. Not
because I like process, but because I would hate to tell you after two weeks of
work that I had pictured it differently.

**Small fix, typo, obvious bug:** straight to a PR, no issue needed.

A useful bug issue contains what happened and what you expected, both in one
sentence; step by step how to get there; the iOS version and device or simulator
model; and whether it happens with a goal, in count-only mode, or in both. If it
involves the AI, say which provider and which log mode — and **do not paste your
key, your photo or your meal text into an issue.** "Doesn't work" is not
reproducible, and I cannot fix what I cannot reproduce.

From there: branch, small commits, PR, review, merge. I read every PR myself and
comment. Everything I raise gets closed before the merge — including the small
things, and including the ones where you talk me out of my position. Then I
merge to `main`.

## Branches

You work in your fork, but the same rule applies there: **never on `main`.** Keep
it clean so you can branch off it at any time without your own work in the way.

Pull once before every new branch, otherwise your PR sits on the state of the
day before yesterday and you rebase afterwards:

```bash
git fetch --all --prune
```

The name carries a prefix that says what it is about. Lowercase, hyphens,
specific. `feat/mistral-provider-client` says something, `feat/settings` says
nothing.

| Prefix | For |
|---|---|
| `feat/` | New functionality |
| `fix/` | Bug fixes |
| `hotfix/` | Urgent fixes to a released version |
| `security/` | Security, hardening, key handling |
| `refactor/` | Restructuring without behaviour change |
| `perf/` | Runtime and memory |
| `design/` | Interface and styling |
| `feedback/` | Changes from review feedback |
| `ci/` | Automation, pipelines |
| `deps/` | Dependencies |
| `migration/` | Store schema and data migrations |
| `docs/` | Documentation only |
| `test/` | Tests only |
| `chore/` | Maintenance, tooling, configuration |
| `spike/` | Experiment, will be discarded |
| `release/` | Preparing a version |
| `revert/` | Undoing something |

No prefix named after the tool you used. **The branch is named after the work,
not after the hammer.** A branch name is read by the next person trying to find
where something happened, and "which editor was open" is not what they are
looking for.

One branch, one topic. If a larger piece turns up mid-way that stands on its
own, open a branch for it. Two topics in one PR mean I have to accept or reject
both together.

## Commits

**Conventional Commits, description in English:** `type(scope): description`.
Scope optional but welcome. Types in use here: `fix`, `feat`, `test`,
`refactor`, `chore`, `design`, `docs`, `build`, `perf`, `security`, `revert`.

The description says **what now holds**, not what you did. Anything non-obvious
gets its reason in the body.

**One commit = one logical change.** No collection commits, no "fix stuff", and
formatting never in the same commit as logic. If you straighten an indentation
while reading a file: separate commit, or not at all.

**No tool trailers.** No `Co-Authored-By`, no "Generated with", no session IDs,
no mention of any tool — not in commits, not in PR titles or bodies, not in code
comments, not anywhere in this repository. If something helped you write it:
good, that is your business and it does not belong in the history.

**Everything in this repository is English.** Code, comments, commit messages,
branch names, issues, pull requests, the interface, the string catalog. Unlike
its sibling Score, Fuel has no German in it — not even in a comment.

Rebased on current `main`, no merge commits in the PR.

## Pull requests

A PR body says three things, and it can say them in three sentences:

- **What changed.** Not a diff summary — I can read the diff. The behaviour that
  is different now.
- **Why.** The issue it closes, the bug it fixes, the design value it corrects.
  If it touches a screen, say which of the seventeen.
- **How to test it.** The steps to see it working, and which mode to be in —
  goal or count only, light or dark, key present or key missing. If it touches
  the AI, say which provider you tested against.

Plus, if any of them apply: what you deliberately did **not** do, what you are
unsure about, and where you want a second opinion. A PR that flags its own weak
spot gets a faster review, not a harsher one.

Review your own PR before I see it: no commented-out remains, no `print`, no
unused files, no formatting outside the scope.

## Tests

They live in `FuelTests/` and use **Swift Testing** (`@Test`, `@Suite`,
`#expect`), not XCTest.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Fuel.xcodeproj -scheme Fuel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

**The nutrition core is where the tests live.** It is pure and value-based, so
there is no excuse. Things worth testing, concretely:

- daily totals and macro arithmetic, including a day with nothing in it
- the goal-versus-count-only split, and that count-only computes no goal
  fraction at all
- the meal-label rule, and this is the one that earns its tests: the first entry
  of a day; a second entry inside the breakfast window, which is a snack; an
  entry at 16:00 on a day with no lunch, which is lunch; a second dinner; a day
  of nothing but snacks; an entry the user relabelled by hand, which stays
  relabelled
- key-format validation, which needs no network and is therefore tested
- provider clients against **recorded response shapes** — never a live endpoint

**Every fix ships with a test that fails without it**, and the counter-check is
mandatory: pull the fix out, watch the test go red, put it back, watch it go
green. A regression test nobody has ever seen fail is decoration — it asserts
something that was already true and will keep passing after the bug comes back.

A red run does not get merged, not even when the red test "was already weird
before". If a test is genuinely wrong, fix it in its own commit and write down
why it was wrong.

**Views are not unit-tested.** They are checked by hand in the simulator against
`design/`: light and dark, and for anything on the day screen both counting
modes. Every time a screen changes.

## Code style

**Nothing enforces style** — no SwiftLint, no SwiftFormat, no `.editorconfig`.
So match the file you are editing.

- **Four spaces**, no tabs.
- `// MARK: -` in any file with more than one type or more than a handful of
  functions.
- **No numeric or colour literals outside the design layer.** No `.padding(17)`,
  no `Color(hex:)`, no hand-rolled `timingCurve` in a feature file. A missing
  value goes into `FuelMetrics`, `FuelPalette`, `FuelTypography` or `FuelMotion`.
- **Every visible string is a catalog key.** No literal in a view.
- No `print`, no `debugPrint`, no commented-out leftovers, no `TODO` without a
  name and a reason beside it. Preferably no `TODO` at all.
- **Formatting is never in the same commit as logic.**

### Comments

Comments explain the **why**, not the what. A comment describing what the line
below it does is wasted. One explaining why it is not the obvious approach saves
the next person half a day — whole paragraphs above a single constant are
deliberate here, not an accident. The meal-label rule is the place this pays
for itself.

**A comment that promises something the code does not do is worse than no
comment**, because people believe it and stop reading the code underneath. If
you change behaviour, pull the comments along — including the ones in
neighbouring files that repeat the same promise.

## Documentation belongs to the change

Three files describe what Fuel is. Whoever changes the behaviour changes them in
the **same PR**, not afterwards:

| File | When it is due |
|---|---|
| [`README.md`](README.md) | When something changes that the README states: a feature, a log mode, the architecture rules, the build commands, numbers. |
| `CONTRIBUTING.md` | When how you contribute changes — a new test command, a new structure, a new rule. |
| [`CLAUDE.md`](CLAUDE.md) | When a rule in it no longer matches this file. It is the condensed version and it goes stale silently. |

Documentation nobody pulls along is worse than none after three months, because
by then people believe it. For pure bug fixes and refactorings usually nothing
is due. When in doubt, one line too many.

## How Claude is used here

Claude is a tool in this repository: code review, boilerplate, structure, a
second pair of eyes on a design spec. That is all it is, and I would rather say
so plainly than have you guess whether it is frowned upon here.

**It is not a substitute for understanding.** Every change is understood and
answered for before it is merged. If I cannot explain what a line does and why
it is there, it does not go in — no matter which tool produced it, including
when the tool is me at one in the morning. That is the difference between using
a tool and vibe-coding, and it is why the reviewer is never the writer: an agent
that fixes what it just found has reviewed nothing, and neither has a person who
reviews their own diff.

It is the same bar I hold your PRs to. You open it, you stand behind it, you can
explain every line in it — including the ones you did not type yourself. What I
do not want are PRs that visibly nobody read: half-fitting comments, tests that
assert nothing, code that happens to go green. The tool is not my business; the
result is.

There is a [`CLAUDE.md`](CLAUDE.md) in the repository with the project rules —
the nutrition core without a database and without a view, BYOK with no fallback,
the design layer as the only source for colour, size and motion. If you work
with a tool that reads it, point it at `CLAUDE.md`, `CONTRIBUTING.md`,
`README.md` and `design/` before it touches anything. That costs you one
sentence and saves you the round where you straighten out literals afterwards.

And: **nothing in this repository mentions the tool.** No attribution in
commits, in PR text, in comments or in files. See "Commits".

## Hard rules

> A PR that breaks these is closed without a discussion of its contents. Not out
> of pedantry: I read every PR myself, in my own time. A contribution where I
> first have to sort commits apart costs me more time than writing it myself.

1. **Small single commits.** One commit = one logical change. Formatting never
   together with logic.
2. **No tool trailers, no AI attribution**, anywhere in the repository.
3. **Conventional Commits, in English.** The description says what now holds.
4. **Everything in English**, including comments and the interface.
5. **Values come from `design/`.** Nothing invented, nothing rounded, nothing
   "close enough".
6. **No numeric or colour literals outside the design layer**, and no visible
   string outside the catalog.
7. **A fix ships with a test that fails without it**, counter-checked.
8. **No red tests.** A run that is not green is not delivered.
9. **No key outside the Keychain**, and no logging of key, photo, meal text or
   model reply.
10. **No Levo Studio call path, no proxy, no bundled key.** BYOK has no
    fallback.
11. **No network code outside `Core/AI/`**, and no dependency — ask first, both
    are deliberate absences.
12. **No changes to `Fuel.xcodeproj/project.pbxproj`** you did not intend, and
    never `DEVELOPMENT_TEAM` or the bundle identifier.
13. **Nothing in `design/` is edited.** The export is read-only.
14. **Documentation pulled along in the same PR.**
15. **Rebased on current `main`, no merge commits.**

## Credits

Contributors keep their authorship. Submitting a pull request grants Levo Studio
the right to use the contribution in the project and in any release Levo Studio
may publish; it does not transfer authorship, and it never has. That is section
4 of the [`LICENSE`](LICENSE), and it holds in both directions.

The visible half of that deal is the credits. **Once your PR is merged you add
yourself to the [credits in the README](README.md#credits) — in the same PR as
the contribution**, not as a separate "add me" PR afterwards. One row: your
name, your GitHub handle, what you contributed in one line, and the PR number.
That is how you get named; nobody has to remember to do it for you.

The rules there are not negotiable:

- **One row, one contribution.** No paragraphs, no logos, no banners, no
  company links.
- **The entry goes in the same PR as the contribution.**
- **Only what is actually in.** One line, not an essay.
- **GitHub handle instead of an email address.** No private contact details,
  neither yours nor anyone else's.
- **Not an advertising slot.** No own products, agencies, services or crypto
  projects. A link to your GitHub profile is the link you get.
- **No other people's names.** You add yourself, nobody else.

An entry that ignores this gets removed without comment.

## License

Fuel is **source-available and strict** (see [`LICENSE`](LICENSE)). Reading,
changing, building and running it on your own devices is allowed.
**Distribution is not.** Not the App Store, not any other store, not TestFlight
including your own, not sideloading to third parties, not handing a compiled
build to anyone. No sale and no transfer for money. No presenting yourself as
the author or provider of Fuel, and no use of the name, the mark, the logo, the
app icon or the visual design for your own product. Fuel is and stays a product
of Levo Studio.

The one exception is the fork you work in: a **source-only public fork** on a
code-hosting platform, notices left intact, for preparing a contribution or for
your own use. That is why the workflow above starts with one. It covers source
code only — a compiled binary still goes to nobody, including the people testing
your branch. The conditions are in section 3 of the license.

All of that binds you, not Levo Studio: the rights stay here, and if Fuel is
ever released, it is released by Levo Studio.

Please do not propose a distribution path the license does not allow, and please
do not ask me to soften the text so one fits.

## Contact

Questions, ideas, or uncertainty about whether something is worth it:
**julius@levo-studio.com**

Better to ask once too often than to build two weeks in the wrong direction.
