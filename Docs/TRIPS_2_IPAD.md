# Trips 2.0 iPad implementation

## Files

Created under `Homey/Features/Trips/`:

- `TripModels.swift`: canonical Trip response, status/duration, date/time helpers from iPhone (editor-only types omitted).
- `Trips2Models.swift`: confirmed Saved ideas, feedback, attention responses, immutable-safe idea payloads from iPhone.
- `Trips2Service.swift`: Home-scoped reads, authenticated planning, RLS idea insert/edit/archive, existing feedback/attention RPC contracts.
- `TripIdeaPlanningAttempt.swift`: iPhone's account/Home/idea-scoped request journal; immutable request UUID and schedule across retry/relaunch.
- `TripsHubSort.swift`: deterministic case-insensitive Saved sorting, dated Planned ascending, Past descending, undated last.
- `TripsServiceError.swift`: title validation error.
- `TripsHubSupport.swift`: load state with Home-switch and stale-response protection.
- `TripCalendarPreparation.swift`: normalized canonical-Trip/Home-scoped Calendar payload.
- `TripCalendarService.swift` and `TripCalendarSubmission.swift`: existing Calendar service adapter and guarded submission/recovery.
- `TripsView.swift`: three independently scrolling columns, detail/editor/archive sheets, Home feedback, Plan Again.
- `TripQuickPlan.swift`: visible start/end date fields, optional times, default-on Calendar option and canonical Trip/Calendar recovery.
- `TripModalComponents.swift`: Calendar-style sheet layout, inset fields/detail panels, banners and secondary actions shared by all Trips modals.

Modified `Homey/Features/MainApp/Views/HomeDashboardPlaceholderPages.swift` to remove only the placeholder TripsView. The existing dashboard already routes to TripsView. Pre-existing edits in the dashboard and Xcode UI state were preserved. The synchronized Xcode source group includes new Swift files automatically.

Tests: `Tests/TripsHubChecks.swift`, `Tests/check-trips-hub-contracts.py`, `Tests/run-trips-hub-checks.sh`, `Tests/TripCalendarSubmissionChecks.swift`.

## UI and behavior

The hub follows Meals' 1180-point content width, 34-point outer spacing, 20-point card inset, equal-width columns, warm theme colors and rounded surfaces. It inherits the dashboard gradient. Each column has its own ScrollView and pull-to-refresh. Swipe-down refresh works even with short or empty columns; foregrounding also reloads data. Switching Home clears data and closes sheets; stale loads cannot publish into the new Home.

Trip Details, Saved Idea details, Add/Edit Idea, Plan Again and Quick Plan use Calendar’s event-editor presentation: a warm background, 720-point centered content, rounded 30-point card, inset fields, large heading and bottom action buttons.

Saved ideas remain permanent when planned. All members get add/edit/archive actions, with RLS enforcing authorization. Edits never send immutable identity, ownership or timestamp fields. Details show title, destination, notes and visit statistics; ratings appear only when rated visits exist. Archive is confirmed and never deletes historical Trips.

Planned uses the shared canonical Trip RPC; it does not filter by organizer Home or insert copies of invited Trips. Duplicate response IDs are collapsed. No invitation acceptance UI was added; Trips already joined through iPhone invitation codes are visible through the same RPC. Planned is chronological per this request. The accessible iPhone currently sorts Planned alphabetically, so that behavior was deliberately not copied. Undated records are last, alphabetically tied.

Past uses end date, then start date, descending, matching the accessible iPhone implementation. The confirmed get_home_trips model has no completion timestamp; no completion-date column was invented. Past cards/details load selected-Home feedback rather than treating the legacy canonical rating as this Home's review. Review writing and completion management remain in iPhone; reload/foreground reflects those changes.

Plan Again opens a prefilled **new Saved idea** editor, then opens that idea to plan new dates with the same durable planning workflow. This intentionally creates a permanent idea rather than calling the non-idempotent legacy clone RPC. Historical Trips are never edited. This is a two-step flow: Save Idea, then Plan This Trip. It can produce another Saved idea if the family already saved that destination; it does not silently guess or merge idea identities.

## Backend contracts reused

Active calls:

- `get_home_saved_trip_ideas(requested_home_id)`.
- `get_home_trips(requested_home_id)`; `trip_id` is the canonical identity, including joined Trips.
- `plan_saved_trip_idea(requested_home_id, requested_idea_id, requested_start_date, requested_end_date, requested_start_time, requested_end_time, requested_request_id)`, returning a UUID. Nullable arguments are explicitly encoded as null.
- `get_trip_household_feedback(requested_home_id, requested_trip_id)`.
- RLS-backed `trip_ideas` insert: `home_id`, `created_by` from auth session, title/destination/address/duration/notes; database owns UUID/timestamps.
- RLS-backed idea updates/archive filtered by both `home_id` and `id`.

The copied service retains confirmed `link_trip_to_saved_idea`, pending-review, awaiting-completion, public submit/dismiss review contracts for compatibility; the hub does not call them or expose admin review helpers.

Calendar creation now reuses iPad `CalendarService.createEvent`, backed by the same `create_calendar_event` RPC as iPhone. See the integration update for current details and limitations.

## Calendar integration update

The current live Calendar workflow and its verification are documented in [TRIP_CALENDAR_FIX.md](TRIP_CALENDAR_FIX.md). The previous local-only Calendar draft fallback has been replaced by the existing iPhone-equivalent `create_calendar_event` workflow. No backend change is required. Add to Calendar is checked by default in quick planning, and the planned Trip detail action also creates Calendar events. Session duplicate prevention and conservative uncertain-response recovery do not imply global backend idempotency.

## Verification

Run `zsh Tests/run-trips-hub-checks.sh`.

Executed checks pass for decoded Saved A–Z ordering; dated/undated Planned order; Past order; joined organizer visibility; trimmed creation payload and server-owned UUID/timestamps; required title; account/Home isolation; request serialization, reload and repeated save; unresolved-request replacement rejection; completion cleanup; all-day multi-day DST and timed drafts; draft overwrite deduplication. Source-contract checks cover the always-visible end date and Calendar choice and Calendar action in details, persistence-before-RPC, Home-filtered mutations, canonical ID deduplication, three scrolling columns and reuse of the existing Calendar create API and refresh notification.

These are standalone Swift behavior tests plus source-contract checks, not live Supabase integration or rendered UI tests. They do not prove RLS, backend request idempotency or invite acceptance. No authenticated account was used or backend data changed.

Simulator SDK build succeeded using Xcode.app explicitly because xcode-select points to CommandLineTools:

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Homey.xcodeproj -scheme Homey -sdk iphonesimulator -derivedDataPath /tmp/HomeyTripsDerived CODE_SIGNING_ALLOWED=NO build`

Build includes Meals and Calendar. Their feature sources were not edited. Interactive landscape, live backend and Meals/Calendar regression checks remain manual, as below.

## Exact manual iPad checks

See [the current Calendar fix report](TRIP_CALENDAR_FIX.md#verification-and-remaining-manual-checks) for the current checked/unchecked, timed/multi-day, recovery, cross-device and regression checks. Saved add/edit/archive and independent three-column scrolling should also be checked in landscape on iPad Pro and iPad mini.
