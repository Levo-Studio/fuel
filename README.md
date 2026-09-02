# Fuel

Calorie tracker for iOS 26 · SwiftUI · SwiftData

[**Case study**](https://juliusgrimm.dev/projects/fuel) ·
[Contributing](CONTRIBUTING.md) ·
[BYOK](#byok--the-key-is-yours) ·
[Building](#building-and-testing)

---

Calorie tracking without selling your soul. No account, no cloud, no 12-screen
onboarding — just type what you ate and move on.

Counting calories is a two-second decision that most apps turn into a
four-minute errand. You open the app, you search a database for "cottage
cheese", you get nineteen entries with different brands and one of them is
somebody's guess from 2014, you pick one, you set a portion, you confirm. Do
that three times a day and you stop doing it by Thursday.

And that is only the part after the sign-up. Before any of it there is an
account, an email address, a body weight, a target weight, a birth date, an
activity level, a notification permission and a paywall — all of it to add two
numbers together and compare the result to a third one.

Fuel takes a photo or a sentence and gives you the numbers. That is the product.

|  |  |
|---|---|
| **Log modes** | Camera, text, recent meals. No manual food search. |
| **Storage** | SwiftData on the device. No account, no cloud, no CloudKit, no sync. |
| **AI** | Bring your own key — Anthropic or Mistral, straight from the device. |
| **Tests** | Swift Testing, in the nutrition core, which knows no database and no view. |
| **Language** | English, string catalog maintained by hand |
| **License** | Source-available — read, build, run. No distribution of any kind. |

How it came about, why it looks the way it does and what got cut is in the
**[case study](https://juliusgrimm.dev/projects/fuel)**.

## What it is

Fuel is a calorie tracker for iOS 26, written in SwiftUI with SwiftData for
local persistence. First launch asks for an AI key, then for one decision: a
daily calorie goal, or count only. After that you are on the day.

Everything lives on the device. No backend, no account, no login, no CloudKit,
no sync, no export. That is not a roadmap item that has not happened yet, it is
the product. There is nothing to sync, so there is nothing to leak.

**With a goal**, the day shows a ring, the total against the goal, and three
macro bars. **Count only** is not the same screen with the ring switched off —
it is a different layout: the total reads "kcal logged", the macros are a plain
row of numbers, and there are no bars, because there is nothing to fill them
against.

Entries are filed into Breakfast, Lunch, Snack and Dinner automatically, and the
rule is deliberately not a clock lookup. Breakfast, lunch and dinner are each
handed out **once a day**, the first time an entry falls into that meal's
window; everything else is a snack. So a second entry at breakfast time is a
snack, and an entry at four in the afternoon on a day with no lunch yet is
lunch, because the lunch window went by unused. You can overwrite the label on
the result screen, and once you have, Fuel leaves it alone.

## Three log modes

The log flow has three tabs and the tab bar draws three.

1. **Camera** — photograph the plate. The image is compressed on the device and
   sent to your provider, which comes back with the items it recognised, an
   estimated amount for each and a confidence.
2. **Text** — write the meal in a sentence: "2 eggs with 200g cottage cheese".
   The more exact the amounts, the more exact the estimate. Amounts you give are
   marked as recognised, amounts you leave out are marked as estimated, so you
   can see which numbers are yours and which ones are a guess.
3. **Recent** — the meals you have logged before. One tap logs the meal again
   with the label derived from the time of day. **Recent needs no key and no
   network at all** — it is your own history, on your own device.

Either estimate lands on a result screen where you can correct the calories in
steps of ten and change the label before it is saved.

**There is no manual food search, and there is not going to be one.** A search
mode was considered and cut. It is the part everyone hates and the reason a
tracker gets abandoned; adding it back would be adding back the problem. Three
modes, and the third one covers everything you eat regularly anyway.

### The camera shortcut

Fuel exposes an App Intent that opens straight into the camera log screen. Put
it on the Home Screen, in the Action Button, or wherever you keep shortcuts —
one press and you are photographing the plate, not navigating to the place where
you photograph the plate.

## BYOK — the key is yours

**Fuel uses AI exclusively with a key you bring.** You fetch a key from
Anthropic or from Mistral, you paste it in, and the app talks to that provider
directly from your device. Levo Studio never sees a request and could not read
one if it wanted to.

This is not a limitation that a later version relaxes. It is why the app can
exist at all:

- **There is no server to run.** No backend means no uptime, no scaling, no
  operations, no thing that goes down while you are standing in a kitchen.
- **There is no bill to pay for someone else's API calls.** Photo recognition is
  not free, and an app that pays for it needs a subscription, and a subscription
  needs an account, and an account needs an email address. That chain starts
  with the first hosted API call, so Fuel does not make one.
- **There are no request logs, because there is no place they could exist.**
  Not a promise about a retention policy — no server, no logs.
- **You stay anonymous.** There is no Levo Studio account, and no Levo Studio
  anything else either. There is your device, your key, and your provider.

Concretely:

- The key lives in the **Keychain**, never in `UserDefaults`, with
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, and **iCloud Keychain sync is
  off** — a synced key would travel through Apple's cloud, which is exactly what
  a local-first app is supposed to avoid. One entry per provider, so you can
  hold both keys and switch without losing the other.
- **Nothing is logged.** Not the key, not a prefix of it, not the photo, not the
  text you typed, not the model's reply. The only place a meal's content is
  written down is its SwiftData entry.
- A new key gets a **format check first**, then one smallest-possible test call,
  so a typo costs you no tokens. The result is shown right there, not discovered
  at the first photo.
- **Images are compressed on the device before they are uploaded.** You are
  paying for those tokens.
- **No Levo Studio key ships in the binary** — not in source, not in an
  `xcconfig`, not in an `Info.plist`. There is no fallback path and no proxy.
  If you have no key, the camera and text modes are disabled and Recent still
  works.

The key setup is the first thing you see and there is no skip button, because
two of the three log modes are AI. You can change or remove the key later in
Settings; the disabled states exist for exactly that.

## Architecture

```
Fuel/
  Core/Design/     FuelPalette, FuelTypography, FuelMetrics, FuelMotion
  Core/Data/       the SwiftData store
  Core/Keychain/   the provider-key wrapper
  Core/AI/         provider clients, request and response shapes
  Models/          FoodEntry and friends — @Model types
  Nutrition/       pure calculation: totals, macros, the meal-label rule
  Features/        one folder per screen area
  Resources/       fonts, Localizable.xcstrings
FuelTests/         Swift Testing
design/            the design export — read-only, never edited to match the code
```

**The nutrition core knows no database.** `Fuel/Nutrition/` works on plain
`Sendable` values, not on `@Model` classes. Totals, macro splits and the
meal-label rule are pure functions over pure values, which is what lets their
tests run in milliseconds without a `ModelContainer` and without a simulator.
Nothing from SwiftData travels deeper than the hand-off type.

**The nutrition core knows no view either.** No `@Observable`, no `Color`, no
`import SwiftUI`.

**Colour, size and motion come only from the design layer.** No `.padding(17)`
and no `Color(hex:)` in a feature file. A missing value goes into `FuelMetrics`,
`FuelPalette`, `FuelTypography` or `FuelMotion`, not into the call site. *Reduce
Motion* is handled centrally in `FuelMotion` — spread over a hundred call sites
it would be forgotten at ninety of them.

**There is no network code outside `Core/AI/`.** If a view is building a
`URLRequest`, the design of that feature is wrong.

Fuel has no dependencies, and that is a feature.

## Building and testing

You need **Xcode 26**. `xcode-select` points at the CommandLineTools on many
machines, and those cannot build an iOS project. Either switch it permanently
(`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`) or prefix
each call:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Fuel.xcodeproj -scheme Fuel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Fuel.xcodeproj -scheme Fuel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

`CODE_SIGNING_ALLOWED=NO` means **you do not need a developer team** to build
Fuel. There are no entitlements and no capabilities hanging off someone's App
Store access, so nothing has to be signed to run in the simulator, and a fresh
clone builds without an Apple Developer account.

### Building to a device

The repository is public, so no development team is stored in the project at
all. Nothing above needs one. Running Fuel on a physical iPhone does, and Xcode
would otherwise write the team you pick straight back into `project.pbxproj`. So
it lives outside the project instead: copy `Local.xcconfig.example` to
`Local.xcconfig`, put your own Team ID in, and build. `Base.xcconfig` includes
it optionally, so a clone without it still builds. `Local.xcconfig` is ignored
by git and cannot end up in a commit.

The project uses synchronized folders — new files under `Fuel/` and `FuelTests/`
join the target on their own, and `Fuel.xcodeproj/project.pbxproj` does not have
to be touched for that.

## Contributing

How a contribution should look, what a useful issue contains, what the commits
have to look like and what `design/` being the source of truth means in
practice: **[CONTRIBUTING.md](CONTRIBUTING.md)**.

Short version: small single commits, tests with the fix, and every value taken
from the design export rather than from taste.

## Credits

**Creator and maintainer**

[**Julius Grimm**](https://github.com/justthatrandomcoder) — idea, design,
nutrition core. [Levo Studio](https://levo-studio.com)

**Contributors**

<!-- Please append new rows at the bottom, alphabetical by name.
     Format: | Name | @github | What | PR | -->

| Name | GitHub | Contribution | PR |
|---|---|---|---|
| _nobody yet — be the first row_ | | | |

Once your PR is merged you may add yourself here. There are rules for that, and
they are not negotiable:

- **One row, one contribution.** No paragraphs, no logos, no banners, no
  company links.
- **The entry goes in the same PR as the contribution**, not as a separate
  "add me" PR.
- **Only what is actually in.** The contribution is described in one line, not
  in an essay: "Mistral client", "fix in the snack rule", "accessibility of the
  log tabs".
- **GitHub handle instead of an email address.** No private contact details,
  neither yours nor anyone else's.
- **Not an advertising slot.** No links to your own products, agencies,
  services or crypto projects. A link to your GitHub profile is the link you
  get.
- **No other people's names.** You add yourself, nobody else.

An entry that ignores this gets removed without comment. Otherwise: whoever is
listed here contributed something that people use on their devices. That is the
point.

## License

Source-available, and stricter than it looks. Read the code, clone it, change
it, build it and run it on devices you own. That is the whole of it.

**No distribution.** Not the App Store, not any other store, not TestFlight —
not even your own — not sideloading to somebody else, not handing a compiled
build to a friend. No sale and no transfer for money. No presenting yourself as
the author or provider of Fuel, and no use of the name "Fuel", the Levo Studio
mark, the logo, the app icon or the visual design for your own product. Fuel is
and stays a product of Levo Studio.

The one narrow exception is the fork contributing needs: a **source-only public
fork**, notices intact, source code and nothing else. A compiled binary goes to
nobody, including the people testing your branch. The conditions are in section
3 of the license.

None of that binds Levo Studio, which holds the rights and keeps them. Anyone
contributing by pull request grants Levo Studio the rights to use the
contribution in the project and in any release Levo Studio may publish — but
keeps their authorship and is named in the [credits](#credits).

The full text is in [`LICENSE`](LICENSE). Read section 3 before you suggest
anything involving a store, TestFlight or sideloading.

© 2026 Levo Studio
