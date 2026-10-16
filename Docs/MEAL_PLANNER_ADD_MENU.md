# iPad Meal Planner add menu fix

## Root cause

`HomeDashboardView` mounts `MealsHomeHubView` for the active Meals destination. That hub has its own `MealsHomeHubViewModel` and `HomeMealPicker`. Both its meal-section header plus and empty-card plus assigned `pickerContext` and opened `HomeMealPicker` directly. They never used the earlier `QuickMealAddChoice` gateway, which was only connected to `MealPlannerView` and `UpcomingMealsPreviewView`.

The separate weekly/Upcoming implementation also presented its choice UI inside a sheet and dismissed that sheet while immediately assigning a second recipe-confirmation sheet. This handoff was an additional presentation-state risk, not the cause of the hub's missing options.

## Changes

Every slot add control now uses the shared native SwiftUI `MealSlotAddMenu`, anchored to its existing label. Its fixed action order is Quick Add, then Recipes. Selecting an action captures an immutable `MealSlotAddRoute` containing Home, date, meal type and destination. Repeated selections are ignored while a route is presented. A Home is required. No sheet opens merely to display the choices.

- Active Meals hub: all four Breakfast/Lunch/Dinner/Snack section-header plus buttons and all four empty-card plus buttons.
- Weekly planner: every date/type slot plus.
- Upcoming Meals: all existing slot-header plus buttons and empty-slot actions. The currently unused standalone empty-row component also uses the shared menu.
- List planner: selected-date add row with one menu for each of the four types. Previously this view had no slot-add controls.

Quick Add presents the existing `QuickMealEditor`; no duplicate editor or persistence implementation was added. The active hub now loads its existing Quick Add ViewModel for the visible date and displays existing `QuickMealRows` alongside recipe cards, so a successful save is visible immediately. Pull-to-refresh and Calendar-change notifications refresh the appropriate data.

Recipes opens the existing hub `HomeMealPicker` or the existing weekly/Upcoming `MealPlannerPickerView`, as appropriate. Weekly/Upcoming recipe selection and confirmation now share one sheet host; there is no dismiss-one/present-another race. Existing recipe-saving methods are unchanged. Hub recipe selection checks its captured Home/date before saving. Home/date changes invalidate the active hub presentation.

No Supabase, SQL, migration, iPhone, recipe-creation, Quick Add RPC or recipe persistence changes were made for this fix. The only ViewModel adjustment accepts an optional selected day when loading the existing planner, allowing the actual hub to reuse it for its navigated date.

## Swift files changed for this fix

- `Homey/Features/Meals/Views/MealsHomeHubView.swift`
- `Homey/Features/Meals/Views/MealPlannerView.swift`
- `Homey/Features/Meals/Views/QuickMealViews.swift`
- `Homey/Features/Meals/Services/MealPlannerViewModel.swift`
- `Homey/Features/Meals/Models/MealSlotAddRoute.swift` (new navigation model)
- `Tests/MealSlotAddRouteChecks.swift` (new)

## Verification

`zsh Tests/run-quick-meal-checks.sh` passes:

- Menu action order and destinations, all four types, captured Home/date/type, no presentation without a Home, ignored repeated actions, and cancellation releasing the route for a fresh presentation.
- Source contracts verify both actual hub entry points use the native menu, both hub destinations use the original views, weekly/Upcoming use one sheet host with in-place confirmation, list adds share the menu, and Quick Add still uses the installed RPC service.
- Existing Quick Add payload, idempotent identity, normalization, Clear Meals V2 decoding, error classification and production Auto Plan checks remain passing.

`git diff --check` passes. The Homey iPad simulator configuration build succeeds with Xcode, generic iOS Simulator destination, signing disabled. Build log: `/tmp/homey-menu-build.log`.

Live simulator UI control was not approved, so landscape visual/tap tests and authenticated save tests were not performed. The native menu is attached to each actual button rather than a screen-level sheet/popover anchor, but landscape visibility is not claimed as a tested result.

Manual acceptance: in iPad landscape open Meals, tap each header and empty-card plus for all four types, verify Quick Add and Recipes are visible and tappable. Choose Quick Add and confirm date/type, enter Wingstop and Save; verify the same date's card refreshes. Choose Recipes, select an existing Home recipe and verify the intended slot. Repeat in weekly, Upcoming and list views; rapidly repeat add taps and confirm only one editor/picker opens. Change Home/date between presentations and confirm the next sheet uses the new context. Do not create or delete production data solely for testing.
