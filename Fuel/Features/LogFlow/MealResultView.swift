import SwiftUI

// MARK: - Footer action

/// What the filled footer button says and does.
///
/// A parameter of the result screen rather than something the screen decides,
/// because the screen is drawn for more than one errand. After an estimate it
/// is `Add`; a screen opened on a meal that is already in the store has a
/// different verb for the same place, and neither should mean a second copy of
/// the drawing.
///
/// There is exactly one thing the screen decides for itself — see
/// `MealResultView.primaryAction`.
struct MealResultAction {

    let title: String

    let perform: () -> Void
}

// MARK: - Footer confirmation

/// The words on the dialog that stands in front of throwing the user's work
/// away.
///
/// A parameter for the same reason `MealResultAction`'s title is one: the
/// mechanism is identical on every errand and the sentence is not. After an
/// estimate, what is at stake is the estimate — nothing has been written down
/// yet, and `Discard` is literally what happens to it. On a meal that is
/// already in the store, nothing is discarded and the meal survives either way;
/// what is at stake is the breakdown edits the user has just made.
///
/// One value rather than two, because one dialog stands in front of both
/// controls that can reach it — the trash mark and `‹ Back` — and on any screen
/// that draws both, both risk the same thing.
nonisolated struct MealResultConfirmation {

    let title: String

    /// The destructive verb.
    let confirm: String

    /// The way out, which changes nothing.
    let cancel: String
}

// MARK: - Meal result

/// Screens 14 and 15: what the model came back with, before any of it is
/// written down.
///
/// **One screen, drawn twice.** The export's two result frames differ in three
/// things and in nothing else: what sits above the meal-label pill — the
/// captured photo on 14, the typed sentence on 15 — the flow label top right,
/// and the heading over the breakdown. All three are a slot and two strings,
/// handed in by whichever screen this is.
///
/// The export draws a fourth difference, the second line of a breakdown row
/// (`Screens2c.dc.html`, lines 336 to 338 against 376 to 378), and **the owner
/// has removed it** — see `itemRow`. With it gone the two frames share the
/// whole breakdown, not only its geometry.
///
/// Everything else from the pill down is the same drawing, down to each
/// padding, so the screen is written once.
///
/// It follows the theme rather than the camera surface — the export draws both
/// on `bg`, not on `cam`, because the estimate is done and there is no
/// viewfinder left to keep legible.
///
/// The estimate's **title is not drawn here.** Neither frame gives the result
/// a heading of its own. The title still travels in the draft and still
/// becomes the entry's name in the day list; these screens simply do not show
/// it.
///
/// Presentation only: it is handed a draft and hands back taps, so it renders
/// in a preview without a store, a client or a camera.
struct MealResultView<Lede: View>: View {

    let draft: MealResultDraft

    /// `Photo entry` or `Text entry`, top right.
    let flowLabel: String

    /// `Recognised` or `Broken down`, over the breakdown.
    let itemsHeading: String

    let onBack: () -> Void
    let onCycleLabel: () -> Void
    let onToggleFavourite: () -> Void

    /// The trailing control on a breakdown row: throw this line out.
    let onRemoveItem: (RecognisedItem.ID) -> Void

    /// The row itself: the user has rewritten this line.
    let onEditItem: (RecognisedItem.ID, String) -> Void

    /// The `Add item` row at the foot of the list.
    let onAddItem: (String) -> Void

    /// Re-estimates the meal from the edited list. Drawn only once something
    /// in that list has changed.
    let onReanalyse: () -> Void

    /// The leading footer control: throw this estimate away without logging
    /// it.
    ///
    /// Optional, because it is only a control where there is something to
    /// throw away. A screen opened on a meal that is already in the store has
    /// nothing to discard, and draws no leading control at all.
    let onDiscard: (() -> Void)?

    /// What the confirmation in front of both of those says. Handed in the way
    /// `flowLabel` is: the screen draws it, the caller knows what is at stake.
    let discardConfirmation: MealResultConfirmation

    /// The filled footer button as this caller means it.
    let commit: MealResultAction

    /// What the mode puts where the other mode puts its own: the thumbnail on
    /// screen 14, the quoted sentence on screen 15. It is the first thing in
    /// the scrolling column and carries its own top inset from the header.
    @ViewBuilder let lede: () -> Lede

    @Environment(\.fuelPalette) private var palette

    /// Which line the field is open on, and `nil` while it is open on a new
    /// one. Both cases are the same field, which is the point: an item is a
    /// sentence, and correcting one and writing one are the same act.
    @State private var editedItem: RecognisedItem.ID?

    @State private var isEditingItem = false

    @State private var editedText = ""

    @State private var isConfirmingDiscard = false

    /// What the confirmation does if it is confirmed.
    ///
    /// One dialog stands in front of two controls — the trash mark, and
    /// `‹ Back` when there is something to lose — so what it carries out is
    /// held here rather than wired into either of them.
    @State private var pendingDiscard: (() -> Void)?

    init(
        draft: MealResultDraft,
        flowLabel: String,
        itemsHeading: String,
        onBack: @escaping () -> Void,
        onCycleLabel: @escaping () -> Void,
        onToggleFavourite: @escaping () -> Void,
        onRemoveItem: @escaping (RecognisedItem.ID) -> Void,
        onEditItem: @escaping (RecognisedItem.ID, String) -> Void,
        onAddItem: @escaping (String) -> Void,
        onReanalyse: @escaping () -> Void,
        onDiscard: (() -> Void)?,
        discardConfirmation: MealResultConfirmation,
        commit: MealResultAction,
        @ViewBuilder lede: @escaping () -> Lede
    ) {
        self.draft = draft
        self.flowLabel = flowLabel
        self.itemsHeading = itemsHeading
        self.onBack = onBack
        self.onCycleLabel = onCycleLabel
        self.onToggleFavourite = onToggleFavourite
        self.onRemoveItem = onRemoveItem
        self.onEditItem = onEditItem
        self.onAddItem = onAddItem
        self.onReanalyse = onReanalyse
        self.onDiscard = onDiscard
        self.discardConfirmation = discardConfirmation
        self.commit = commit
        self.lede = lede
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            palette.background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: .zero) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: .zero) {
                        lede()
                        labelRow
                        caloriesRow
                        macroRow
                        itemList
                    }
                    .padding(.top, FuelMetrics.Space.s26)
                    .padding(.horizontal, FuelMetrics.Screen.horizontalPadding)
                    // The footer floats over the list, so the last row has to
                    // be able to clear it.
                    .padding(.bottom, FuelMetrics.Space.s96)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            footer
        }
        // A system alert with one field, rather than a sheet drawn in the
        // app's own language. The export has no editor of any kind, so
        // anything here is undrawn; the platform's own answer is the honest
        // one, and it brings the ordinary keyboard, the cancel that changes
        // nothing and the focus behaviour for free.
        .alert(MealResultCopy.itemEditTitle, isPresented: $isEditingItem) {
            TextField(MealResultCopy.itemEditPlaceholder, text: $editedText)

            Button(MealResultCopy.itemEditCancel, role: .cancel) {}

            Button(MealResultCopy.itemEditConfirm) { commitItemEdit() }
        } message: {
            Text(MealResultCopy.itemEditMessage)
        }
        // The platform's own confirmation, for the same reason the item field
        // is: the export draws no modal of any kind, so a drawn one would be a
        // second undrawn surface where iOS already has the honest answer.
        // `confirmationDialog` rather than `alert` because this is a
        // destructive action being confirmed, which is the sheet's whole
        // subject, and it puts the destructive verb where the platform's users
        // look for it.
        .confirmationDialog(
            discardConfirmation.title,
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button(discardConfirmation.confirm, role: .destructive) { pendingDiscard?() }

            Button(discardConfirmation.cancel, role: .cancel) { pendingDiscard = nil }
        }
    }

    /// Puts the confirmation in front of something that throws the user's work
    /// away.
    private func confirmDiscard(_ perform: @escaping () -> Void) {
        pendingDiscard = perform
        isConfirmingDiscard = true
    }

    // MARK: - The item field

    private func beginEditing(_ id: RecognisedItem.ID?, text: String) {
        editedItem = id
        editedText = text
        isEditingItem = true
    }

    /// What `Done` on the field does. An empty field is refused by the draft
    /// itself, so a user who opened `Add item` and thought better of it leaves
    /// nothing behind.
    private func commitItemEdit() {
        if let editedItem {
            onEditItem(editedItem, editedText)
        } else {
            onAddItem(editedText)
        }
        editedText = ""
        editedItem = nil
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: FuelMetrics.Space.s14) {
            Button(action: back) {
                Text(MealResultCopy.back)
                    .fuelStyle(FuelTypography.eyebrow)
                    .foregroundStyle(palette.muted)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(MealResultCopy.backLabel))

            Spacer(minLength: FuelMetrics.Space.s14)

            Text(flowLabel)
                .fuelStyle(FuelTypography.flowLabel)
                .foregroundStyle(palette.muted)
        }
        .padding(.top, FuelMetrics.Space.s22)
        .padding(.horizontal, FuelMetrics.Screen.logFlowHorizontalPadding)
    }

    /// `‹ Back`, which leaves the estimate behind.
    ///
    /// It goes through the same confirmation the trash mark does, **but only
    /// once the user has changed the breakdown**, and the condition is the
    /// whole point. The export draws no confirmation on this control, and a
    /// prompt on an untouched screen would be a dialog in front of nothing —
    /// so with nothing edited this is immediate, exactly as drawn. With
    /// something edited it is a control that silently throws away text the user
    /// typed, standing beside one that asks first.
    ///
    /// `hasItemEdits` and not "anything at all was touched": the label pill and
    /// the favourite mark are single taps that are redone in a single tap, and
    /// gating on those would put the dialog back in front of nothing.
    ///
    /// Both modes get it. What is at risk is the item corrections, and both
    /// backs destroy those identically — the text mode keeping the sentence
    /// does not bring back a single rewritten row.
    private func back() {
        guard draft.hasItemEdits else {
            onBack()
            return
        }
        confirmDiscard(onBack)
    }

    // MARK: - Label and favourite

    private var labelRow: some View {
        HStack(alignment: .center, spacing: FuelMetrics.Space.s14) {
            mealLabelPill
            Spacer(minLength: FuelMetrics.Space.s14)
            favouritePill
        }
        .padding(.top, FuelMetrics.Space.s24)
    }

    /// The pill cycles Breakfast → Lunch → Snack → Dinner and wraps, which is
    /// `MealLabel.next` and the day list's own order. It is a cycle rather than
    /// a menu because the export draws a chevron on a pill, not a picker.
    private var mealLabelPill: some View {
        Button(action: onCycleLabel) {
            HStack(alignment: .center, spacing: FuelMetrics.Space.s7) {
                Text(MealResultCopy.mealLabel(draft.label))
                    .fuelStyle(FuelTypography.tabLabel)
                    .foregroundStyle(palette.ink)

                ChevronGlyph()
                    .stroke(
                        palette.ink,
                        style: StrokeStyle(lineWidth: FuelMetrics.Line.Glyph.chevron, lineCap: .round, lineJoin: .round)
                    )
                    .frame(
                        width: FuelMetrics.Line.Glyph.chevronWidth,
                        height: FuelMetrics.Line.Glyph.chevronHeight
                    )
            }
            .padding(.vertical, FuelMetrics.Space.s8)
            .padding(.horizontal, FuelMetrics.Space.s14)
            .overlay {
                RoundedRectangle(cornerRadius: FuelMetrics.Radius.pill)
                    .strokeBorder(palette.hair, lineWidth: FuelMetrics.Line.hairline)
            }
            .contentShape(.rect(cornerRadius: FuelMetrics.Radius.pill))
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(MealResultCopy.mealLabel(draft.label)))
        .accessibilityHint(Text(MealResultCopy.mealLabelHint))
        .fuelAnimation(FuelMotion.standard, value: draft.label)
    }

    private var favouritePill: some View {
        Button(action: onToggleFavourite) {
            Text(MealResultCopy.favourite(isOn: draft.isFavourite))
                .fuelStyle(FuelTypography.tabLabel)
                .foregroundStyle(draft.isFavourite ? palette.onAccent : palette.muted)
                .padding(.vertical, FuelMetrics.Space.s8)
                .padding(.horizontal, FuelMetrics.Space.s13)
                .background {
                    RoundedRectangle(cornerRadius: FuelMetrics.Radius.pill)
                        .fill(draft.isFavourite ? palette.accentColor : .clear)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: FuelMetrics.Radius.pill)
                        .strokeBorder(
                            draft.isFavourite ? palette.accentColor : palette.hair,
                            lineWidth: FuelMetrics.Line.hairline
                        )
                }
                .contentShape(.rect(cornerRadius: FuelMetrics.Radius.pill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(MealResultCopy.favouriteLabel))
        .accessibilityAddTraits(draft.isFavourite ? [.isButton, .isSelected] : .isButton)
        .fuelAnimation(FuelMotion.standard, value: draft.isFavourite)
    }

    // MARK: - Calories

    /// The figure and its unit, on the row the export puts them on.
    ///
    /// **The export also draws a `−` and a `+` in circles at the trailing end
    /// of this row** — a ±10 kcal stepper, `Screens2c.dc.html` lines 325 and
    /// 326 on screen 14 and 365 and 366 on screen 15, inside the wrappers at
    /// 324 to 327 and 364 to 367, with the step in `design/Fuel Design Notes.md`
    /// under "Result stepper". The owner has removed it: a figure the user
    /// nudges ten at a time is guesswork on top of the model's guess, and the
    /// way to correct an estimate is now to correct the items it was made from
    /// and ask again.
    ///
    /// The figure still animates, because it still changes — a re-analysis
    /// replaces it.
    private var caloriesRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: FuelMetrics.Space.s8) {
            Text(LogFlowFormat.figure(draft.kilocalories))
                .fuelStyle(FuelTypography.resultCalories)
                .foregroundStyle(palette.ink)
                .contentTransition(.numericText())

            Text(MealResultCopy.unit)
                .fuelStyle(FuelTypography.unit)
                .foregroundStyle(palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(MealResultCopy.kilocaloriesValue(draft.kilocalories)))
        .padding(.top, FuelMetrics.Space.s22)
        .fuelAnimation(FuelMotion.value, value: draft.kilocalories)
    }

    // MARK: - Macros

    private var macroRow: some View {
        HStack(alignment: .top, spacing: FuelMetrics.Space.s24) {
            macro(MealResultCopy.macroProtein, draft.macros.protein)
            macro(MealResultCopy.macroCarbs, draft.macros.carbs)
            macro(MealResultCopy.macroFat, draft.macros.fat)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, FuelMetrics.Space.s20)
        .padding(.bottom, FuelMetrics.Space.s20)
        .overlay(alignment: .bottom) {
            palette.hair
                .frame(height: FuelMetrics.Line.hairline)
        }
    }

    private func macro(_ name: String, _ grams: Int) -> some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text(name)
                .fuelStyle(FuelTypography.macroLabelSmall)
                .foregroundStyle(palette.muted)

            Text(MealResultCopy.grams(grams))
                .fuelStyle(FuelTypography.macroValue)
                .foregroundStyle(palette.ink)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Breakdown

    private var itemList: some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text(itemsHeading)
                .fuelStyle(FuelTypography.sectionLabel)
                .foregroundStyle(palette.muted)

            ForEach(draft.items) { item in
                itemRow(item)
            }

            addItemRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, FuelMetrics.Space.s18)
        .fuelAnimation(FuelMotion.standard, value: draft.items)
    }

    /// One line of the breakdown: what it is, what it costs, and the two
    /// things the owner has added to it — a tap to rewrite it and a mark to
    /// throw it out.
    ///
    /// **The export draws a second line under the name** — `confident · approx.
    /// 150 g` after a photo, `Amount recognised` after text — and the owner has
    /// removed it. It was the one thing on these screens that differed by log
    /// mode, so the row is now literally the same row on both frames.
    ///
    /// **The export draws no control on this row at all.** The two here are
    /// recomposed from what it does draw: the name and the figure keep their
    /// type, their colour and the row's `s13` padding and `hairSoft` rule, and
    /// the remove mark takes the figure's size and the `muted` the export gives
    /// a secondary mark. Nothing moved to make room for either.
    ///
    /// It does **not** take the figure's face — see `removeControl` for why it
    /// cannot.
    ///
    /// `RecognisedItem.Note` is untouched: it is stored with the entry and is
    /// read outside this screen. Nothing draws it here any more.
    private func itemRow(_ item: RecognisedItem) -> some View {
        HStack(alignment: .center, spacing: FuelMetrics.Space.s14) {
            Button {
                beginEditing(item.id, text: item.name)
            } label: {
                HStack(alignment: .center, spacing: FuelMetrics.Space.s14) {
                    // Model-written text, already capped at 120 characters at
                    // the parse boundary, or the user's own. Plain `Text`, so
                    // there is no markup path into the interface for a name
                    // that arrived from a provider.
                    Text(verbatim: item.name)
                        .fuelStyle(FuelTypography.itemTitle)
                        .foregroundStyle(palette.ink)

                    Spacer(minLength: FuelMetrics.Space.s14)

                    // A line the user has written has no price yet, and the
                    // device does not make one up. It stays blank until the
                    // re-analysis fills the whole list in.
                    if draft.isPriced(item.id) {
                        Text(LogFlowFormat.figure(item.kilocalories))
                            .fuelStyle(FuelTypography.listValueSmall)
                            .foregroundStyle(palette.ink)
                    }
                }
                // The padding sits inside the button so the region that answers
                // to a finger is the whole drawn row, not the height of the
                // name.
                .padding(.vertical, FuelMetrics.Space.s13)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: item.name))
            .accessibilityValue(Text(MealResultCopy.kilocaloriesValue(item.kilocalories)))
            .accessibilityHint(Text(MealResultCopy.itemEditHint))

            // Not drawn on the last remaining row, because there it cannot do
            // anything — see `MealResultDraft.canRemoveItems`. **Hidden rather
            // than inert**, and the choice is the one this screen has just been
            // through: a control that is drawn and does nothing is the dead
            // `Re-analyse` again, and the export gives no dimmed state to draw
            // instead. Hiding it needs no value the design does not carry — the
            // mark is an addition to a drawn row, so a row without it is the row
            // the export actually draws, name and figure and nothing else.
            if draft.canRemoveItems {
                removeControl(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            palette.hairSoft
                .frame(height: FuelMetrics.Line.hairline)
        }
    }

    /// The remove mark at the trailing edge of a row.
    ///
    /// A symbol stands in for a character neither bundled face can draw. The
    /// obvious mark is the `✕` the export writes into screen 07's cancel
    /// control, and it cannot be set in DM Mono: **U+2715 is not in that font's
    /// cmap** — U+00D7 and U+0058 are, U+2715 and U+2699 are not — so what the
    /// export proves on screen 07 is that the browser satisfied it from a
    /// fallback face, not that the bundled one carries it. On a device CoreText
    /// cascades and there is no tofu, but the mark would be drawn in whatever
    /// system face answers, beside a figure drawn in DM Mono.
    ///
    /// That is exactly the situation `TodayView`'s gear is in, and this is the
    /// same answer: an SF Symbol, disclosed here, so what is drawn is decided
    /// rather than left to a cascade. `FuelMetrics.Line.Glyph`'s stroke weights
    /// do not apply to a symbol — SF draws its own. The size and the colour are
    /// the row's.
    ///
    /// Drawn at its natural width and given a `minimumHitTarget` box to answer
    /// in, aligned trailing so the mark itself stays on the margin and the
    /// extra region grows inwards, across the gap it already has to the figure.
    /// The row keeps its drawn height: the box's vertical reach is the row's
    /// own `s13` padding, which is what the `.rect` shape below covers.
    private func removeControl(_ item: RecognisedItem) -> some View {
        Button {
            onRemoveItem(item.id)
        } label: {
            Image(systemName: "xmark")
                .fuelStyle(FuelTypography.listValueSmall)
                .foregroundStyle(palette.muted)
                .frame(minWidth: FuelMetrics.Control.minimumHitTarget, alignment: .trailing)
                .padding(.vertical, FuelMetrics.Space.s13)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(MealResultCopy.itemRemoveLabel))
    }

    /// The last row of the list, which is not an item.
    ///
    /// **Not in the export.** It is the item row with its figure and its remove
    /// mark taken away and the name replaced by a label, so it keeps the same
    /// padding, the same rule under it and the same type — a row that reads as
    /// the end of the list rather than as a button parked beneath it. Muted
    /// rather than ink, because it names an action and not a thing the user
    /// ate.
    private var addItemRow: some View {
        Button {
            beginEditing(nil, text: "")
        } label: {
            Text(MealResultCopy.itemAdd)
                .fuelStyle(FuelTypography.itemTitle)
                .foregroundStyle(palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, FuelMetrics.Space.s13)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            palette.hairSoft
                .frame(height: FuelMetrics.Line.hairline)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .center, spacing: FuelMetrics.Space.s10) {
            if let onDiscard {
                discardControl(onDiscard)
            }

            Button(action: primaryAction.perform) {
                Text(primaryAction.title)
                    .fuelStyle(FuelTypography.buttonLabel)
                    .foregroundStyle(palette.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FuelMetrics.Space.s17)
                    .background(palette.accentColor, in: .rect(cornerRadius: FuelMetrics.Radius.pill))
                    .contentShape(.rect(cornerRadius: FuelMetrics.Radius.pill))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, FuelMetrics.Screen.horizontalPadding)
        .padding(.bottom, FuelMetrics.Space.s34)
        .fuelAnimation(FuelMotion.standard, value: draft.hasItemEdits)
    }

    /// The leading footer control.
    ///
    /// **Deviation from the export, on the owner's instruction.** Screens 14
    /// and 15 draw an outlined pill here reading `Neu` → `New`. What it
    /// actually does is throw the estimate away, and the owner wants it to
    /// read as that: a trash mark and no word.
    ///
    /// The pill does not move and does not change size. Its `s17`/`s20`
    /// padding, its `Radius.pill` hairline outline, its `chipLabel` type and
    /// its `ink` are the drawn ones; only what sits inside it changes, and the
    /// pill is already past a fingertip in both directions at that padding.
    ///
    /// A symbol stands in for a glyph the export does not draw and the bundled
    /// faces cannot render — the same situation as Today's gear, and the same
    /// answer. `FuelMetrics.Line.Glyph`'s stroke weights do not apply to a
    /// symbol: SF draws its own.
    ///
    /// It asks every time, unlike `‹ Back` above, which asks only once there
    /// is something to lose. This control's whole subject is throwing the
    /// estimate away, so a confirmation in front of it is never a dialog in
    /// front of nothing.
    private func discardControl(_ perform: @escaping () -> Void) -> some View {
        Button {
            confirmDiscard(perform)
        } label: {
            Image(systemName: "trash")
                .fuelStyle(FuelTypography.chipLabel)
                .foregroundStyle(palette.ink)
                .padding(.vertical, FuelMetrics.Space.s17)
                .padding(.horizontal, FuelMetrics.Space.s20)
                .overlay {
                    RoundedRectangle(cornerRadius: FuelMetrics.Radius.pill)
                        .strokeBorder(palette.hair, lineWidth: FuelMetrics.Line.hairline)
                }
                .contentShape(.rect(cornerRadius: FuelMetrics.Radius.pill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(MealResultCopy.discardLabel))
    }

    /// What the filled button is right now.
    ///
    /// **Not in the export**, which draws `Hinzufügen` and nothing else in this
    /// place. Once the user has changed the list, the figures above it describe
    /// a breakdown that no longer exists, and logging them would write down a
    /// meal nobody estimated. So the button asks the model again instead.
    ///
    /// **Unless the list is empty**, in which case there is nothing to ask
    /// about and the caller's own action comes back. See
    /// `MealResultDraft.canReanalyse`, which holds both halves of that rule so
    /// this button and the request it fires cannot disagree — they used to, and
    /// a footer reading `Re-analyse` over an emptied list did nothing at all
    /// while hiding the action it had replaced.
    ///
    /// It is the one thing this screen decides rather than takes as a
    /// parameter, and deliberately: the rule is the same for every caller, and
    /// a caller that forgot it would be a caller that logs a stale figure.
    ///
    /// **It replaces the caller's action rather than sitting beside it.** Every
    /// press spends the user's own API credit, so it appears only while
    /// something has actually changed and never as a second button standing
    /// permanently on the screen. Nothing re-analyses on its own.
    private var primaryAction: MealResultAction {
        guard draft.canReanalyse else { return commit }
        return MealResultAction(title: MealResultCopy.reanalyse, perform: onReanalyse)
    }
}

// MARK: - Chevron

/// The chevron beside the meal-label pill, as the export draws it:
/// `M1 1l3.5 3.5L8 1` in a 9×6 box — a 45° V held one unit off the left, the
/// right and the top.
///
/// A path rather than a symbol: it is the one glyph the export authors outside
/// the 20-unit box, and `chevron.down` is neither this angle nor this weight.
private struct ChevronGlyph: Shape {

    nonisolated func path(in rect: CGRect) -> Path {
        let scale = rect.width / FuelMetrics.Line.Glyph.chevronWidth
        let inset = FuelMetrics.Line.Glyph.chevronInset * scale
        let top = rect.minY + inset
        // The V descends by exactly the distance it travels sideways.
        let drop = rect.midX - (rect.minX + inset)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + inset, y: top))
        path.addLine(to: CGPoint(x: rect.midX, y: top + drop))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: top))
        return path
    }
}
