import Foundation
import Observation

// MARK: - Root shell model

/// Decides what the app opens on, and holds the state that must outlive a
/// re-render.
///
/// Both halves are the same concern. The launch decision is not a stored flag:
/// it is read from the store, because the existence of the `GoalSettings` row
/// is what "onboarding has been answered" means. A second boolean beside it —
/// in `UserDefaults`, in the keychain, anywhere — would be a second answer to
/// one question, and the two would eventually disagree.
@MainActor
@Observable
final class RootShellModel {

    // MARK: - Stage

    enum Stage: Equatable {
        case onboarding
        case today
    }

    // MARK: - Destination

    /// What is presented over Today.
    ///
    /// Both are full-screen presentations rather than pushes, because each is
    /// dismissed by a control the export draws on its own chrome: the log
    /// flow's `✕ Cancel` at the top left of screens 07, 12 and 13, and
    /// Settings' `Done` opposite its title on screens 16 and 17. Neither is a
    /// back chevron in a navigation bar, and no screen in the export draws one
    /// — so there is nothing for a stack to draw, and a stack would put its own
    /// bar above screens that are laid out from the top of the frame.
    ///
    /// **The logged-meal screen is not one of these**, and it is the one
    /// destination the export draws no frame for at all. It is reached by
    /// tapping a row in a list, which is the one thing iOS pushes, so it is
    /// pushed — see `pushedMeal`.
    enum Destination: Hashable, Identifiable {

        case logFlow
        case settings

        var id: Self { self }
    }

    // MARK: - Composition

    /// Builds the camera half of a log flow for the provider that is selected
    /// at the moment the flow opens.
    typealias CameraLogFactory = @MainActor (FuelStore, AIProvider) -> CameraLogModel

    /// The real thing: the device camera, and the client for that provider.
    ///
    /// The provider is passed twice on purpose and they are not the same
    /// question. `client` decides which endpoint an estimate is sent to;
    /// `provider` decides which key the model looks for before it lets the
    /// shutter work. Handing the model a Claude client while it checked for a
    /// Mistral key would put a dead shutter in front of a working account.
    @MainActor
    static let liveCameraLog: CameraLogFactory = { store, provider in
        CameraLogModel(
            store: store,
            client: ProviderClients.client(for: provider),
            camera: AVFoundationCamera(),
            provider: provider
        )
    }

    /// Builds the text half of a log flow for the same provider, at the same
    /// moment.
    typealias TextLogFactory = @MainActor (FuelStore, AIProvider) -> TextLogModel

    /// The real thing: the client for that provider, and no camera — screen 12
    /// sends a sentence.
    ///
    /// The provider is passed twice for the reason it is above, and the two
    /// questions are the same two: which endpoint the estimate is sent to, and
    /// which key the model looks for before it lets `Analyse` do anything.
    @MainActor
    static let liveTextLog: TextLogFactory = { store, provider in
        TextLogModel(
            store: store,
            client: ProviderClients.client(for: provider),
            provider: provider
        )
    }

    /// Builds the screen a logged meal opens on, for the provider that is
    /// selected at the moment the row is tapped.
    ///
    /// `nil` when there is no such meal — see `MealDetailModel.init`.
    typealias MealDetailFactory = @MainActor (FuelStore, AIProvider, UUID) -> MealDetailModel?

    /// The real thing: the client for that provider, and no camera. A stored
    /// meal is re-estimated from its item list.
    ///
    /// The provider is passed twice for the reason it is above, and the two
    /// questions are the same two: which endpoint a re-analysis is sent to, and
    /// which key the model looks for before it makes one.
    @MainActor
    static let liveMealDetail: MealDetailFactory = { store, provider, entryID in
        MealDetailModel(
            entryID: entryID,
            store: store,
            client: ProviderClients.client(for: provider),
            provider: provider
        )
    }

    // MARK: - Dependencies

    private let store: FuelStore

    /// The three preferences Settings stores. Held rather than read once,
    /// because the provider a scan talks to is whichever one is selected when
    /// the flow is opened — not the one that was selected at launch.
    private let preferences: SettingsPreferences

    /// How the camera half of a log flow is built.
    ///
    /// A seam rather than a direct call, and it earns its keep twice.
    /// `CameraLogModel` keeps its client, its keychain reader and the provider
    /// it looks a key up under to itself, so without this nothing outside it
    /// could establish that the provider Settings stores is the provider the
    /// next scan uses. It is also the only way a test reaches this screen at
    /// all: the real composition opens the device camera and builds a client
    /// pointed at a provider's endpoint.
    private let makeCameraLog: CameraLogFactory

    /// How the text half of a log flow is built, and a seam for the same two
    /// reasons: `TextLogModel` keeps its client and its provider to itself, and
    /// the real composition points a client at a provider's endpoint.
    private let makeTextLog: TextLogFactory

    /// How the screen for a logged meal is built, and a seam for the same two
    /// reasons: `MealDetailModel` keeps its client and its provider to itself,
    /// and the real composition points a client at a provider's endpoint.
    private let makeMealDetail: MealDetailFactory

    // MARK: - State

    private(set) var stage: Stage

    private(set) var destination: Destination?

    /// What Today draws, worked out from the store rather than kept in step
    /// with it: it is recomputed whenever the stage becomes `today`, which is
    /// the only moment its inputs can have changed while no log flow exists.
    private(set) var today: TodayPresentation

    /// Which day Today is showing, and which days it can move to.
    ///
    /// **The export draws no navigation on screens 05 and 06** — one day, and
    /// no way to leave it. Browsing back is the owner's instruction; the rules
    /// of it are `TodayDayNavigation`'s, and what is held here is only which
    /// day is up.
    ///
    /// Rebuilt with the presentation and never separately, because its two
    /// bounds are read from the same store: the day it stops at is the day of
    /// the first meal ever logged, and deleting that meal moves it.
    private(set) var dayNavigation: TodayDayNavigation

    /// Whether the last day change moved to an earlier day.
    ///
    /// Held rather than worked out where the day is drawn, because a transition
    /// has to be chosen *before* the change is applied and a view watching the
    /// day can only see it afterwards. It is also the one thing the three
    /// controls share: a swipe, an arrow and a jump to the same day all travel
    /// the same way because all three set this.
    private(set) var dayTravelIsBackward = false

    /// What Today draws in the day list's place while the day is empty.
    ///
    /// Recomputed with `today` and never separately. Its three answers come
    /// from two places — the preferences hold the theme and the accent, and the
    /// store answers whether a meal was ever logged — and all three can change
    /// behind a presented cover, so the moment they are read is the moment the
    /// cover goes away.
    private(set) var gettingStarted: TodayGettingStarted

    /// The onboarding flow's own state, built once so a re-render of the shell
    /// cannot drop a half-typed key or restart the key test.
    ///
    /// It cannot be a `let`: its completion handler captures `self`, which is
    /// only available once every stored property holds a value. Observation is
    /// switched off for it because the reference never changes — the object it
    /// points at is `@Observable` on its own account.
    @ObservationIgnored private(set) var onboarding: OnboardingModel!

    /// The log flow's state, replaced each time the flow is opened.
    ///
    /// A kept model would reopen on whichever tab was left selected, and the
    /// export is explicit about where the flow starts: screen 07 is captioned
    /// `Log · camera (default)`. Nothing is lost by starting again either —
    /// the Recent list is read from the store on appearance, and a flow that
    /// was cancelled had by definition typed nothing worth keeping.
    ///
    /// Observed rather than `@ObservationIgnored`, unlike `onboarding`: this
    /// reference does change, and a presentation still reading the previous
    /// flow's model would show the tab the user left rather than the one they
    /// are opening.
    private(set) var logFlow: LogFlowModel

    /// The camera half of the same flow, rebuilt with it and for the same
    /// reason — more urgently, in fact. `LogFlowModel` would only reopen on
    /// the wrong tab; this one holds a stage, a captured frame and a draft, so
    /// a flow left on a failed scan or on the result screen would reopen onto
    /// that screen instead of onto the viewfinder screen 07 draws. Rebuilding
    /// also releases the frame: a photo the user walked away from has no
    /// reason to stay in memory until the next scan replaces it.
    private(set) var cameraLog: CameraLogModel

    /// The text half of the same flow, rebuilt with it and for the same
    /// reasons the camera half is, plus one of its own. It carries a stage, so
    /// a flow abandoned on a failed estimate or on screen 15 would reopen onto
    /// that screen rather than onto the entry field. And it carries the
    /// sentence the user typed: a flow that was cancelled had, as the note on
    /// `logFlow` puts it, by definition typed nothing worth keeping, and
    /// keeping it anyway would put a meal the user walked away from back in
    /// front of the next one — and hold its content in memory until then.
    private(set) var textLog: TextLogModel

    /// The screen a logged meal opens on, built when a row is tapped and
    /// released when it closes.
    ///
    /// Not kept, for the reason the log flow is not: it holds a draft the user
    /// may have edited without asking for it to be priced, and reopening onto
    /// that would put a meal they walked away from in front of the next one.
    private(set) var mealDetail: MealDetailModel?

    /// Which meal is on the navigation stack over Today, or `nil` when none is.
    ///
    /// Separate from `mealDetail` because the two answer different questions
    /// and a view needs both: this one is the path the stack is driven by, and
    /// the other is the screen at the end of it. It is the identity rather than
    /// the model because a path element has to be `Hashable` and a stack that
    /// carried the model itself would rebuild the screen whenever the model
    /// changed.
    private(set) var pushedMeal: UUID?

    /// Whether leaving the meal screen right now would throw the user's work
    /// away.
    ///
    /// It exists because the system's back-swipe cannot be vetoed. SwiftUI's
    /// interactive pop is a write to the stack's path, and the only thing a
    /// path binding can do with a write it does not want is refuse it — there
    /// is no way to stop the gesture before it finishes. So the pop is asked
    /// about here first, and a shell that gets `true` puts the same
    /// confirmation `‹ Back` raises in front of it rather than letting the
    /// gesture do what the confirmation exists to prevent.
    ///
    /// `hasItemEdits` and not "anything at all was touched", for the reason
    /// `MealResultView.back()` gives: the label pill and the favourite mark are
    /// written to the store as they are tapped, and gating on those would put
    /// the dialog in front of nothing.
    var mealDetailDiscardsEdits: Bool {
        mealDetail?.draft.hasItemEdits ?? false
    }

    /// Settings' API-key row. Built once, because a re-render must not drop a
    /// half-typed key or restart a check in flight — the same reason
    /// `onboarding` is built here rather than in a view.
    @ObservationIgnored private(set) var settingsKey: APIKeySettingsModel

    /// Screen 17's counting mode and its four targets, built when Settings is
    /// opened rather than held from launch.
    ///
    /// Unlike the three preferences beside it, these are store rows — and at
    /// the moment this model is created the store may not have them yet, since
    /// onboarding is what writes the first one. Reading at the launch of the
    /// app would show the user a mode they had not chosen.
    private(set) var settingsCounting: CountingSettingsModel?

    // MARK: - Creation

    /// Where the two models that hold a key write it.
    ///
    /// Injectable for one reason: without it no suite can drive onboarding
    /// past the key screen, because the default store is the real service and
    /// a test run would write into the key of whoever is on the machine — and
    /// its cleanup would delete it. The provider a first launch chooses is
    /// only observable at this level, so the seam is what makes it testable at
    /// all.
    init(
        store: FuelStore,
        validator: KeyValidating,
        preferences: SettingsPreferences,
        keychain: KeychainStore = KeychainStore(),
        makeCameraLog: @escaping CameraLogFactory = RootShellModel.liveCameraLog,
        makeTextLog: @escaping TextLogFactory = RootShellModel.liveTextLog,
        makeMealDetail: @escaping MealDetailFactory = RootShellModel.liveMealDetail
    ) {
        self.store = store
        self.preferences = preferences
        self.makeCameraLog = makeCameraLog
        self.makeTextLog = makeTextLog
        self.makeMealDetail = makeMealDetail
        self.stage = Self.launchStage(for: store)
        // The app opens on the current day, always. A browsed day is not a
        // preference and is not stored: it is where the user walked to in this
        // session, and a launch is not a continuation of it.
        let navigation = Self.navigation(for: store, showing: nil)
        self.dayNavigation = navigation
        self.today = Self.presentation(for: store, on: navigation.day)
        self.gettingStarted = Self.checklist(store: store, preferences: preferences)
        self.logFlow = LogFlowModel(store: store)
        // One read, spent on both halves. Two reads could not disagree today —
        // nothing runs between them — but they are two sources for a value the
        // whole flow has to hold one answer to.
        let provider = preferences.provider
        self.cameraLog = makeCameraLog(store, provider)
        self.textLog = makeTextLog(store, provider)
        self.settingsKey = APIKeySettingsModel(keychain: keychain, validator: validator)
        // The same `preferences` the log flow is built from, not a copy.
        // Onboarding's provider segment writes straight into it, so the
        // provider a user picks at first launch is the one the first scan is
        // built for and the one screen 16 opens on.
        self.onboarding = OnboardingModel(
            keychain: keychain,
            validator: validator,
            store: store,
            preferences: preferences,
            onFinished: { [weak self] in self?.showToday() }
        )
    }

    // MARK: - Launch decision

    /// No settings row means onboarding has never been answered.
    ///
    /// A fetch that throws is read as "not answered". Asking the questions
    /// again is recoverable; opening Today against a store that cannot be read
    /// is not, and onboarding's own write would surface the same failure where
    /// the user can respond to it.
    private static func launchStage(for store: FuelStore) -> Stage {
        let settings = (try? store.existingGoalSettings()) ?? nil
        return settings == nil ? .onboarding : .today
    }

    /// The three answers, each read from whatever actually holds it.
    ///
    /// Static and taking its two sources, so it can run inside `init` before
    /// every stored property has a value — the same reason `presentation` is.
    ///
    /// **Nothing here asks about the key or the counting mode.** Both are
    /// answered by onboarding before Today exists, so neither is a thing to
    /// suggest on the first Today screen.
    private static func checklist(
        store: FuelStore,
        preferences: SettingsPreferences
    ) -> TodayGettingStarted {
        TodayGettingStarted(
            // "Differs from what Fuel ships with", not "has been visited".
            // A user who opens screen 16 and picks the theme it already had
            // has changed nothing, and the row says the look, not the visit.
            hasChosenTheme: preferences.theme != SettingsPreferences.Default.theme,
            hasChosenAccent: preferences.accent != SettingsPreferences.Default.accent,
            // A store that cannot be read is not a store that has been logged
            // to. Failing towards "still to do" keeps the checklist on screen
            // one launch too long, which is recoverable; failing the other way
            // would retire it on someone who has never logged anything.
            hasLoggedMeal: (try? store.hasAnyEntry()) ?? false
        )
    }

    /// The day being shown, in whichever mode the user is counting in.
    ///
    /// **The mode is read for the browse as a whole and not for the day**, and
    /// that is the right reading rather than a shortcut: goal or count-only is
    /// a preference on screen 17, not a property a day carries. A past day
    /// therefore draws whichever of screens 05 and 06 the user is in now, and
    /// its total stands against the goal they hold now. The alternative would
    /// be to store the mode and the targets alongside every entry, which is a
    /// different product.
    private static func presentation(for store: FuelStore, on day: Date) -> TodayPresentation {
        TodayPresentation(
            entries: (try? store.nutritionEntries(on: day)) ?? [],
            mode: (try? store.countingMode()) ?? .goal(.default),
            date: day
        )
    }

    /// Which days can be browsed, read from the store each time.
    ///
    /// A store that cannot be read has no history to walk into, and `nil` there
    /// leaves the current day as the whole range — both arrows dead, the date
    /// jump offering one day. Failing towards "there is nothing behind you" is
    /// the recoverable direction: the worst of it is that a walk back is
    /// refused for one launch, where failing the other way would offer a walk
    /// into days the store cannot answer for.
    ///
    /// - Parameter day: the day to keep showing, or `nil` for the current one.
    private static func navigation(for store: FuelStore, showing day: Date?) -> TodayDayNavigation {
        let now = Date()
        return TodayDayNavigation(
            showing: day ?? now,
            now: now,
            firstEntry: (try? store.earliestEntryDate()) ?? nil,
            // The store's own calendar, not `.current`. Which day an entry
            // belongs to is already its question, and a second calendar here
            // would file a meal into one day and browse to another.
            calendar: store.calendar
        )
    }

    // MARK: - Transition

    /// Called when onboarding has written the settings row. The row is the
    /// truth, so the presentation is read back from the store rather than
    /// assembled from what the flow happened to hold.
    private func showToday() {
        refreshToday()
        stage = .today
    }

    /// Re-reads everything Today draws.
    ///
    /// One call rather than three at each site: the checklist, the day and the
    /// range it sits in are read from the same store at the same moment, and a
    /// site that refreshed only one of them would show a day with an entry in
    /// it beside a row still asking for the first meal.
    ///
    /// The range is re-read with the rest and not treated as fixed. Its far end
    /// is the day of the first meal ever logged, and that meal can be deleted;
    /// the day being shown is handed back to `TodayDayNavigation`, which clamps
    /// it, so a browse standing on a day that has just fallen out of the range
    /// lands on the nearest one still in it.
    private func refreshToday() {
        dayNavigation = Self.navigation(for: store, showing: dayNavigation.day)
        today = Self.presentation(for: store, on: dayNavigation.day)
        gettingStarted = Self.checklist(store: store, preferences: preferences)
    }

    // MARK: - Moving between days

    /// The back arrow in the header, and a drag to the right.
    func showPreviousDay() {
        show(dayNavigation.backward())
    }

    /// The forward arrow, and a drag to the left. Both are refused on today —
    /// the future is not browsable — and the arrow is drawn disabled to say so.
    func showNextDay() {
        show(dayNavigation.forward())
    }

    /// A day chosen in the picker the date opens.
    func showDay(_ day: Date) {
        show(dayNavigation.jumping(to: day))
    }

    /// Comes back to the current day, which is where a logged meal landed.
    func showCurrentDay() {
        show(dayNavigation.jumping(to: dayNavigation.today))
    }

    /// The one place a day change happens, so the three controls cannot differ
    /// in what one is.
    ///
    /// A move that lands where it already stood is dropped rather than applied:
    /// at either bound the arrows are disabled and a swipe simply does nothing,
    /// and re-assigning the same day would run the travel over a screen that is
    /// not changing.
    private func show(_ moved: TodayDayNavigation) {
        guard moved.day != dayNavigation.day else { return }
        dayTravelIsBackward = moved.isBackward(from: dayNavigation)
        dayNavigation = moved
        // The day only — the checklist and the range have not moved, and a full
        // refresh here would re-read the whole store on every swipe.
        today = Self.presentation(for: store, on: moved.day)
    }

    // MARK: - Leaving and returning to Today

    /// The plus on screens 05 and 06.
    func openLogFlow() {
        logFlow = LogFlowModel(store: store)
        // Read here rather than kept from launch, so a provider switched on
        // screen 16 is the one the next estimate talks to and looks a key up
        // under. Nothing has to tell the flow that Settings was used.
        //
        // Read once and spent on both halves: the camera and the text tab of
        // one flow must not be pointed at two different providers.
        let provider = preferences.provider
        cameraLog = makeCameraLog(store, provider)
        textLog = makeTextLog(store, provider)
        destination = .logFlow
    }

    /// A meal in the day list on screens 05 and 06.
    ///
    /// A meal that is no longer there leaves the tap unanswered rather than
    /// opening an empty screen — the same shape the gear uses against a store
    /// it cannot read, and for the same reason: the export draws no state for
    /// either.
    ///
    /// The provider is read here rather than kept from launch, so a provider
    /// switched on screen 16 is the one a re-analysis talks to and looks a key
    /// up under.
    func openMealDetail(_ entryID: UUID) {
        guard let detail = makeMealDetail(store, preferences.provider, entryID) else { return }
        mealDetail = detail
        pushedMeal = entryID
    }

    /// Comes back to Today from the meal screen, by `‹ Back`, by a deletion, or
    /// by the system's pop.
    ///
    /// Separate from `dismissDestination` because a push is not a presentation:
    /// the two cannot be up at once, nothing here has a camera session to stop,
    /// and the meal is released rather than a cover cleared. What the two share
    /// is the re-read, and for the same reason — `today` is worked out from a
    /// fetch rather than a live query, so a meal deleted on this screen is off
    /// Today only once this has run.
    func dismissMealDetail() {
        // Released with the screen, so a second tap on a row builds it again
        // rather than reopening onto edits the user walked away from — and so
        // the meal's breakdown is not held in memory until then.
        mealDetail = nil
        pushedMeal = nil
        refreshToday()
    }

    /// The gear on screens 05 and 06.
    ///
    /// A store that cannot be read leaves the gear unanswered rather than
    /// opening screen 17 against invented defaults. Those fields write back
    /// the moment they are edited, so a user adjusting a 2400 the store never
    /// held would overwrite the goal they actually set — worse than a control
    /// that did nothing, and the export draws no state for either.
    func openSettings() {
        guard let counting = try? CountingSettingsModel(store: store) else { return }
        settingsCounting = counting
        destination = .settings
    }

    /// Comes back to Today from whatever was presented, with the day re-read
    /// from the store.
    ///
    /// **One exit for all four of them** — `✕ Cancel`, a meal logged, `Done`,
    /// and a preference changed on the way out — because the refresh is a
    /// re-read rather than an update. The meal screen is not among them: it is
    /// pushed rather than presented, and leaves through `dismissMealDetail`.
    /// Nothing here is told what happened while
    /// the presentation was up; the store is asked again, and it answers with
    /// the day and the counting mode as they now are. Cancel costs one fetch
    /// that returns the same day, which is the price of not having a second
    /// path that depends on the flow's own account of whether it wrote.
    ///
    /// It is not left to SwiftData to notice, either. `today` is a value
    /// worked out from a fetch, not a live query, so an entry written inside
    /// the flow reaches the totals and its meal section only when this runs.
    func dismissDestination() {
        // The flow starts the session when the camera tab appears and stops it
        // when another tab does, through a `.task(id:)` keyed on the selected
        // tab. Cancelling that task does not stop the session, so nothing
        // stopped it when the whole cover went away — the camera and its
        // indicator would keep running behind Today. It was unreachable while
        // nothing presented the flow; presenting it is what this branch does.
        //
        // Stopping belongs here rather than in the flow because this is what
        // owns the model's lifetime: it builds the camera half when the flow
        // opens and releases it here.
        //
        // **It is not a teardown the flow has of its own**, and that is the
        // cost of putting it here. Every dismissal Fuel can reach funnels
        // through this method — `✕ Cancel`, a meal logged, and the binding
        // `RootShell` clears — so nothing leaks today. A second presenter of
        // `LogFlowView` that did not come through here would leak silently
        // again, and the durable answer if one ever arrives is a teardown
        // beside the `.task(id:)` that starts the session.
        if destination == .logFlow {
            cameraLog.camera.stop()
        }

        refreshToday()
        destination = nil
    }

    /// The one dismissal that is not the same as the others: a meal was logged.
    ///
    /// **A meal is logged now, whatever day Today happens to be showing.** The
    /// log flow takes the device clock — screens 07, 12 and 13 draw no control
    /// for choosing a date, and there is none — so a flow opened while browsing
    /// Tuesday still writes to today. Coming back onto Tuesday would leave the
    /// user looking at a day their meal is not on, with nothing to say where it
    /// went; the honest close is onto the day it landed in.
    ///
    /// Only this exit moves the day. `✕ Cancel` goes through
    /// `dismissDestination` and leaves the browse where it was, because nothing
    /// was written and there is nowhere else to be.
    func dismissDestinationAfterLogging() {
        showCurrentDay()
        dismissDestination()
    }

    // MARK: - Arriving from outside

    /// The "Scan" shortcut, asking for the camera.
    ///
    /// It lands on the plus control's destination — the log flow on screen 07,
    /// the tab the export captions `Log · camera (default)` — and it draws
    /// nothing of its own. Going through `openLogFlow` rather than assigning
    /// `destination` is what keeps it that way: a flow opened from outside is
    /// built against the provider selected now, with both halves fresh, or the
    /// shortcut would be a second composition drifting out of step with the
    /// drawn one.
    ///
    /// A key that is missing is not this method's business and is deliberately
    /// not checked here. The camera half asks the Keychain whether an item
    /// exists when its tab appears and puts screen 07 into its keyless state,
    /// which is a state the user can read and act on — better than a shortcut
    /// that appears to do nothing, and the only reading that does not make the
    /// shell a second place where the key question is asked.
    func requestScan() {
        // Onboarding has not been answered, so there is no Today to present
        // over — and screens 01 to 03 come before 04, so there is no key
        // either. Opening the app is the whole answer available: it lands on
        // the step that has to happen first, which is where a launch would
        // land anyway. A cover over onboarding would put a viewfinder in front
        // of a user who has not yet answered the questions that make a scan
        // possible, and there is no drawn state for that.
        guard stage == .today else { return }

        switch destination {
        case .logFlow:
            // The flow the user is already in is the destination the shortcut
            // asks for, so only the tab is left to answer. Rebuilding it would
            // be the destructive reading of "open the camera": a scan in
            // flight cancelled, a captured frame dropped, a result screen the
            // user had not committed replaced by a viewfinder.
            logFlow.selectedTab = .camera
        case .settings:
            // Only one cover can be presented, so Settings is left the way its
            // own `Done` leaves it — through `dismissDestination`, with the
            // re-read of the day that comes with it — before the flow is opened
            // as the plus opens it. Both writes land in one update, and
            // `fullScreenCover(item:)` replaces the presentation when the
            // item's identity changes, so Today is not shown in between.
            dismissDestination()
            openLogFlow()
        case nil:
            // A meal is pushed rather than presented, so it can be underneath a
            // shortcut with no cover up. It is popped first, the way its own
            // `‹ Back` pops it: the shortcut asks for the camera, not for the
            // camera on top of a meal the user would find again on the way out.
            //
            // **Without the confirmation**, deliberately. The gesture and the
            // drawn control are the user leaving; this is the system handing
            // the app a request from outside, and a dialog raised in front of
            // it would ask a question nobody on this screen just asked. What is
            // lost is the same as on any pop with edits pending — the stored
            // meal is untouched either way.
            if pushedMeal != nil {
                dismissMealDetail()
            }
            openLogFlow()
        }
    }
}
