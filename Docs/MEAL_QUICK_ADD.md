# Quick Add and Clear Meals V2 — iPad integration

## Status

The manually installed backend contracts supplied for this task are integrated. No SQL, migrations, database writes, RLS changes, iPhone changes, Delete Home changes, or physical Storage cleanup changes were made during implementation. Live RPC behavior has not been tested with authenticated devices.

## RPC integration

- `get_quick_meal_plan_entries(requested_home_id, requested_start_date, requested_end_date)` uses Home-local YYYY-MM-DD strings, start-inclusive/end-exclusive. Both the service and ViewModel filter returned entries by Home; the service also filters by range.
- `save_quick_meal_plan_entry(requested_home_id, requested_entry_id, requested_title, requested_planned_date, requested_meal_type, requested_timezone)` uses a stable sheet UUID across retries and the original UUID on edits/reschedules. Optional timezone is omitted when nil, using the backend default. Backend Home timezone remains authoritative.
- `delete_quick_meal_plan_entry(requested_home_id, requested_entry_id)` targets exactly one entry in its Home.
- Swift never creates, updates or deletes a Quick Add Calendar event separately. The save/delete RPCs own those mutations. A missing Meal category is supported because the client does not require a category ID.
- Before an edit/reschedule, the client verifies that the original Quick Add and associated Calendar event still exist in the original Home/date. Missing/stale records produce a reconciliation error and preserve the entered name. No fallback creates another event. The installed server must still enforce transactional integrity for a deletion concurrent with this preflight.

`clear_home_meals_v2(requested_home_id)` replaces the old call. `ClearHomeMealsResult` decodes exactly the installed ten integer counters:

```
meals_deleted, meal_recipes_deleted, recipe_ingredients_deleted,
recipe_steps_deleted, meal_photos_deleted, meal_favorites_deleted,
meal_collections_deleted, meal_collection_items_deleted,
meal_plan_entries_deleted, quick_meals_deleted
```

The original response's `meal_event_details_deleted` and `calendar_events_deleted` fields are no longer required. Settings captures the Home at confirmation, dismisses confirmation on Home/role changes, and checks Owner permission again before calling the existing service's Owner guard. Confirmation text includes Quick Adds. Successful clear posts both Meals and Calendar refresh notifications; failures show an error.

## Planner behavior and safeguards

Weekly, list, and Upcoming Meals show Quick Adds alongside recipes. Existing Home Recipes picker, recipe writes, leftovers and recipe detail behavior remain intact. Text-only cards offer Edit / Reschedule and Remove; removal requires confirmation. Multiple entries per date/type are supported. Bulk week reset includes Quick Adds.

Save trims whitespace and rejects empty titles. Cancel issues no RPC. Save is guarded in the sheet and ViewModel; the stable entry ID also permits server-side idempotency after an ambiguous connection failure. The editor captures its original Home, keeps typed content on errors and does not reinitialize on sheet reappearance. Removal updates local state only after success and reloads. Successful mutations notify the shared Calendar refresh path and reload the planner. Home/range changes and overlapping loads cannot publish an older request's results into a newer Home/range.

Quick Add load errors do not remove loaded recipes. They appear in the planner/preview, with a Refresh control available in both. Auto Plan stops generation if Quick Add occupancy is unavailable, and always reads current Quick Add occupancy before applying a recipe suggestion. Existing Quick Add slots are occupied and cannot be rerolled into recipes. Quick Adds have no recipe/ingredient identity, never enter the Home recipe candidate list, and do not generate leftovers or groceries. The current iPad Generate Shopping List action is still a coming-soon placeholder; no new grocery generation was introduced.

## Validation

Run `zsh Tests/run-quick-meal-checks.sh`:

- Executable model/payload checks: all four lowercase meal types, selected Home/date, trim/empty handling, stable retry/edit/reschedule identity, optional timezone, get/delete payload keys, multiple entries, round-trip decoding, error classification, and all ten Clear Meals V2 counters including zero counts.
- Executable Auto Plan checks against the production engine: all four Quick Add slots remain occupied even with an eligible recipe available; reroll preserves occupied slots; normal recipe suggestions still work without Quick Adds.
- Python source contract checks: recipe picker routing, Cancel, submission guards, Home and range isolation, Calendar reconciliation, mutation refresh, recipe/grocery separation, fail-closed occupancy checks, V2 RPC name and Owner guards.

These are executable model/engine and source checks, not interactive UI or live database tests. Test outcomes and simulator build result are recorded in the chat. Build command:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Homey.xcodeproj -scheme Homey -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/homey-quick-add-build -clonedSourcePackagesDirPath /tmp/homey-quick-packages -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO build
```

## Authenticated device acceptance checks still required

1. On iPad select Home A, Friday Dinner → + → Quick Add → Wingstop → Save. Refresh planner and Calendar. Confirm one entry and one one-hour Calendar event at 18:00 in Home A's timezone. Repeat for Breakfast 08:00, Lunch 12:00 and Snack 15:00. Verify a category-less event if the Home has no Meal category.
2. Refresh the same Home on iPhone. Verify Wingstop appears. Create a Quick Add on iPhone and use the iPad planner Refresh control. Verify reverse visibility. iPhone integration is not modified or assumed verified here.
3. Edit title, reschedule date/type and remove on either device. Refresh both devices and Calendar. Verify the same Calendar event ID is updated for edit/reschedule, and both records disappear on remove.
4. Double-tap Save and retry after an interrupted connection; verify a single entry/event. Verify empty/whitespace cannot save, Cancel creates nothing, errors preserve title, and multiple Quick Adds plus a recipe coexist in a slot.
5. Delete a Calendar event independently while an edit sheet is open, then Save. Expect a reconciliation error rather than recreation. If deletion races the preflight, verify the installed backend's transactional safeguard. Do not claim this concurrency case passed from client checks alone.
6. Switch Homes while loading, editing, removing or confirming Clear Meals. Verify only the selected Home's entries display, an old sheet cannot save to a different Home, and a Home switch invalidates Clear Meals confirmation.
7. Verify Auto Plan does not fill Quick Add slots, preserves recipe planning elsewhere, and fails safely when occupancy cannot be loaded. Verify groceries/leftovers exclude text-only entries.
8. In a disposable test Home, confirm only Owner can Clear Meals; Admin/Member must be denied by UI/service/server. Clear Meals V2 should remove recipes, meal plans, Quick Adds and their events, preserve Explore/Community recipes, and refresh Calendar/planner. Do not run this destructive check on production data.

No additional manual Supabase migration is identified from the supplied installed contracts. If the authenticated checks expose a server inconsistency (permissions, missing-event races, duplicate events or cleanup), report it separately for manual investigation; do not run SQL from this task.

## Swift files touched in finalization

- `Homey/Features/MainApp/Views/HomeSettingsView.swift`
- `Homey/Features/Meals/Services/MealService.swift`
- `Homey/Features/Meals/Services/QuickMealService.swift`
- `Homey/Features/Meals/Services/MealPlannerViewModel.swift`
- `Homey/Features/Meals/Models/ClearHomeMealsResult.swift` (new extracted V2 response model)
- `Homey/Features/Meals/Models/QuickMealError.swift` (new safe error classification)
- `Homey/Features/Meals/Models/QuickPlannedMeal.swift`
- `Homey/Features/Meals/Views/QuickMealViews.swift`
- `Homey/Features/Meals/Views/MealPlannerView.swift`
- `Tests/QuickMealChecks.swift`
- `Tests/QuickMealAutoPlanChecks.swift` (new)

Earlier Quick Add changes to `AutoPlanModels.swift` and `AutoPlanEngine.swift` remain in the working tree.

## Recorded results

- `zsh Tests/run-quick-meal-checks.sh`: PASS, including model/payload/error/V2 decoding checks, production Auto Plan engine checks, category-less Calendar decoding/one-hour duration, preserved recipe-backed occupancy, and both Python source contract suites.
- `git diff --check`: PASS.
- Final Homey iPad simulator configuration build: **BUILD SUCCEEDED**, generic iOS Simulator destination, signing disabled. Log: `/tmp/homey-quick-add-build.log`. Existing UIRequiresFullScreen deprecation and App Intents metadata warnings remain.
- Interactive simulator UI, authenticated Supabase operations, destructive Clear Meals execution, and two-device synchronization: NOT RUN. Follow the acceptance steps above; none are claimed passed.
