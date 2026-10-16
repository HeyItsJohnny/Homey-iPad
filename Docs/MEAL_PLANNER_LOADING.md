# iPad Meal Planner loading isolation fix

## Confirmed client failure path

The active `HomeDashboardView` → `MealsHomeHubView` has two ViewModels:

1. `MealsHomeHubViewModel` loads recipe plan rows from `get_meal_plan_entries`, then joins Home recipes.
2. `MealPlannerViewModel` was reused to load Quick Adds, but first loaded Calendar events, **every accessible `meal_event_details` row**, Home recipes and Calendar categories. Its Quick Add RPC was nested inside that successful recipe/category block.

The user-facing "We could not load your meal plan" text is `MealPlannerServiceError.loadFailed`, thrown by this second, legacy Calendar/recipe loading path. A Calendar/details/recipe decoding/query failure prevented `get_quick_meal_plan_entries` from running at all and produced a blocking alert in the active hub. The same coupling existed in weekly/Upcoming loading.

That dependency and swallowed diagnostic are confirmed in source. No authenticated failing device response was captured in this session. Therefore the precise live underlying Swift error/PostgREST code **cannot be asserted** from the original generic text. In particular, neither a missing relation nor a null `meal_id` in the live database is claimed as observed.

A focused fixture reproduces the additional decoder hazard: a title-only detail row with `meal_id: null` throws `DecodingError.valueNotFound` at `[0].meal_id` if decoded as `[MealEventDetail]`. The original all-row query made unrelated/incompatible detail rows capable of breaking this load. The fixed query is scoped to selected-Home Calendar event IDs and filters `meal_id IS NOT NULL` before decoding recipe details.

## iPhone comparison

Read-only inspection of `/Users/johnnylaroco/Desktop/Homey-iPhone/Homey-iPhone/Features/Meals/QuickMealService.swift` and `QuickPlannedMeal.swift` confirmed the same RPC name, keys and UUID/title/date-string/lowercase-meal-type representation. `planned_date` is a String on both platforms; it should not use a timestamp decoding strategy. No iPhone file was modified.

The supplied installed contract remains:

- RPC: `get_quick_meal_plan_entries`
- Arguments: `requested_home_id`, `requested_start_date`, `requested_end_date`
- Array rows: `entry_id`, `home_id`, `calendar_event_id`, `title`, `planned_date`, `meal_type`
- Date range: start-inclusive, end-exclusive.

## Fix

- The actual Meals hub loads Quick Adds in `quickAddsOnly` mode. Its already-existing `get_meal_plan_entries` recipe loader is independent; loading text-only rows never invokes the legacy recipe-detail join.
- Weekly/Upcoming recipe, Quick Add and category channels run independently. Success in one updates its cards even when another fails. Each channel has its own loading/error state; stale Home/range/revision results cannot publish.
- Quick Add failure remains a specific non-blocking status with **Retry Quick Adds**. Retry only repeats the Quick Add read. Successfully loaded recipe cards remain visible. A genuine failed fetch is never silently converted to an empty array.
- Recipe detail reads are scoped to the selected Home's Calendar event IDs and exclude null recipe IDs at query time. Quick Add Calendar events do not require a recipe detail or a Meal category.
- Quick Add decoding validates date-only YYYY-MM-DD values and the four iPad Quick Add meal types: breakfast/lunch/dinner/snack. Malformed records produce a decoding error with a field path; empty arrays succeed.
- `MealLoadFailure` retains safe diagnostics: exact operation, Swift error kind, PostgREST code when supplied, and decoding coding path. Raw response data, backend messages, titles, Home/entry IDs, tokens and decoding debug descriptions are not logged or displayed. No temporary diagnostic logging was added.
- Read-boundary errors now distinguish `get_quick_meal_plan_entries`, `get_meal_plan_entries`, `get_calendar_events`, `meals.read` and `meal_event_details.read`. A subsequent device failure will expose its actual safe code/field rather than the original generic text.

Quick Add and recipe rows remain separate typed arrays. The hub renders `QuickMealRows` and recipe `MealPlanItem` cards in the same selected-date/type section, retaining multiple entries and original recipe sort order. Weekly/list views retain the existing text-only cards and recipe cards. No Quick Add is resolved as a Home Recipe. No fake recipes, new persistence path, grocery ingredients or leftovers were introduced. Existing mutation RPCs and Calendar refresh notifications are unchanged. Auto Plan still treats Quick Add slots as occupied and fails safely when occupancy cannot be read.

## Swift files changed for this loading fix

- `Homey/Features/Meals/Models/MealLoadFailure.swift` (new safe diagnostics/independent-result helper)
- `Homey/Features/Meals/Models/QuickPlannedMeal.swift`
- `Homey/Features/Meals/Services/QuickMealService.swift`
- `Homey/Features/Meals/Services/MealPlannerViewModel.swift`
- `Homey/Features/Meals/Services/MealPlannerService.swift`
- `Homey/Features/Meals/Services/MealPlanEntryService.swift`
- `Homey/Features/Meals/Services/MealService.swift`
- `Homey/Features/Meals/Services/MealsHomeHubViewModel.swift`
- `Homey/Features/Meals/Views/MealsHomeHubView.swift`
- `Homey/Features/Meals/Views/MealPlannerView.swift`
- `Homey/Features/Calendar/Services/CalendarService.swift` (preserve safe read diagnostics)
- `Tests/MealLoadingChecks.swift` (new)
- `Tests/QuickMealAutoPlanChecks.swift`

## Validation

`zsh Tests/run-quick-meal-checks.sh` exercises:

- iPhone-contract JSON fixtures for all four meal types and date-only decoding with an ISO timestamp strategy configured.
- Empty arrays, malformed/null fields, invalid/uppercase meal types and invalid dates; safe error operation/kind/path/code without fixture-title leakage.
- Production `MealLoadResult` async isolation in both directions: a failed Quick Add decode does not fail the recipe result; a failed legacy recipe read does not prevent a successful Quick Add result.
- Same-slot multiple entries and Home identity; existing production Auto Plan tests now include recipe and Quick Add occupancy on the same date/type.
- Reproduction of the recipe-only decoder's null-meal-ID failure, and source contracts for the scoped/non-null detail query.
- Existing normalization, RPC payload keys, stable mutation IDs, Clear Meals V2 counters, menu routing, Auto Plan, category-less Calendar events and recipe-backed occupancy.

These are fixture/model/engine/source checks, not a claim of live iPhone-to-iPad synchronization. Live authenticated reads, RLS, actual device error reproduction, UI appearance and mutation round trips were not exercised. The Home/range/revision checks and mutation refresh paths are retained and checked in source.

Manual acceptance: on iPhone create a Quick Add in a known Home/date/type. On iPad select the same Home/date and refresh; verify its text-only card alongside a recipe. Test empty and multiple slots, then edit/reschedule/remove and refresh both. Simulate a Quick Add read failure and verify recipe cards remain with a retry status. If any operation still fails, record only the displayed operation/code/coding path; do not share meal titles or response bodies.

No backend change is demonstrated or required by this client fix. No SQL, migrations, RLS, tables or RPCs were changed. If the new diagnostic reveals a backend denial or missing RPC on a live device, investigate that exact code separately rather than modifying the working iPhone/backend speculatively.

## Recorded result

- Full `zsh Tests/run-quick-meal-checks.sh`: PASS, including the new async loading/decoding diagnostics suite and all retained regressions.
- `git diff --check`: PASS.
- Final Homey iPad simulator configuration build: **BUILD SUCCEEDED** (generic iOS Simulator, signing disabled). Log: `/tmp/homey-loading-build.log`.
- Live authenticated device reproduction: not performed; original backend code remains unknown rather than inferred from a generic error.
