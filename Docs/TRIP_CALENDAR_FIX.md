# Trips Add to Calendar — client fix

## Root cause and comparison

This was a client-side omission, not a failed Calendar RPC or a hidden Calendar event. In iPad, TripQuickPlan called `plan_saved_trip_idea`, then closed the sheets. Its Calendar option had been removed in an earlier requested UI change. Trip Details' Add to Calendar called `TripCalendarPreparation.save`, which only wrote UserDefaults. It never called `CalendarService.createEvent`. A temporary backend-contract blocker likewise prevented Calendar creation; that blocker has been removed.

The accessible iPhone code uses:

1. `Features/Trips/SavedTripPlanningView.swift` → `Trips2Service.planIdea` for the canonical Trip. This file itself has no Calendar checkbox.
2. `Features/Trips/TripDetailView.swift` → `TripCalendarCreateView` for Add to Calendar.
3. `TripCalendarDraft.make` prefills title, location, notes, schedule, with category nil until explicitly selected in its editor.
4. `TripCalendarCreateView.add` checks `PhoneCalendarService.matchingTripEvents`, then calls `PhoneCalendarService.create`.
5. `Features/Calendar/CalendarService.swift` invokes **`create_calendar_event`**. There is no canonical Trip association in this RPC. `TripCalendarDuplicateGuard` matches title/location/all-day/start/end; it does not provide global idempotency.
6. On success, iPhone posts `homeyCalendarEventsDidChange`. On an ambiguous write failure it checks Calendar instead of blindly resending.

No iPhone files were changed.

## Fixed iPad workflow

- Keep the existing three-column UI, date-picker auto-dismiss, and Calendar-style detail sheets.
- Plan This Trip shows both dates and a default-on Add to Calendar toggle.
- Persist immutable request UUID, schedule, Calendar choice, and Home timezone before planning.
- Recover the canonical Trip with the same request ID on an ambiguous plan response. Persist a confirmed Trip ID so Calendar retries do not call the planning RPC again.
- With Calendar unchecked, clear the confirmed plan journal, close both sheets and reload Trips. No Calendar read or create runs.
- With Calendar checked, fetch the canonical Trip through `get_home_trips(requested_home_id)`, use its title/destination/notes and date range, and the planning request's optional times and captured Home timezone.
- `TripCalendarSubmission` performs iPhone-style matching, serializes submissions within the screen and calls `TripCalendarService.createEvent` only when needed.
- `TripCalendarService` calls existing iPad **`CalendarService.createEvent`**. That service already supplies the deployed `create_calendar_event` argument names, authenticates, and handles its errors. No speculative RPC is called.
- Category is **nil**, matching iPhone's default prefill, which has no automatic Trip category. No category is invented or inserted. The normal Calendar UI can assign an existing category later.
- With Add Times off, one all-day event starts at midnight on the first day and ends at exclusive midnight after the inclusive final day in the Home timezone. This is the same wire representation as iPhone's Calendar normalization. iPad's Calendar service accepts already-normalized timestamps, so no second day is added.
- With Add Times on, selected wall-clock times are combined with the selected dates in the Home timezone. End must follow start. The checkbox controls timed/all-day behavior; no duration-type heuristic discards the user's selected times.
- On Calendar success or matching existing event, post `.homeyCalendarEventsDidChange` and reload Trips. Successful quick planning closes both sheets without a success banner. Existing Calendar observers reload their data using the same notification as Calendar's own editor.
- If Calendar fails, keep the canonical Trip, refresh Planned, retain recovery information, and show an accurate partial-success error. Retry Calendar uses the existing Trip. Check Calendar is read-only when a write outcome is uncertain. Close and Keep Trip explicitly ends planning recovery; it never deletes the Trip or event.
- Planned Trip Details' Add to Calendar now uses the same live creation/recovery workflow, not a local draft-only action.
- Home/account checks occur before reads/writes. UI updates are guarded after awaits; switching Home cannot redirect an in-flight operation to the newly selected Home. Once started, unstructured tasks retain their operation state through sheet dismissal; confirmed results are recorded under their original account/Home/Trip.

## Existing RPC parameters

The existing iPad Calendar service supplies these verified names, also used by iPhone:

`target_home_id`, `event_title`, `event_notes`, `event_location`, `event_starts_at`, `event_ends_at`, `event_is_all_day`, `event_timezone`, `event_category_id`, `assigned_user_ids`, `event_recurrence_frequency`, `event_recurrence_interval`, `event_recurrence_days_of_week`, `event_recurrence_end_date`, `event_recurrence_count`.

Trips creates a nonrecurring event with no assigned users and default nil category. `CalendarService` owns RPC encoding and normalization; Trips does not maintain a second copy of the parameter encoder.

## Retry limitations — no backend changes required

**No backend change is necessary for the requested iPhone-equivalent functionality. No SQL, migrations, deployments, or RLS changes were performed.**

Generic Calendar creation is **not globally idempotent**. The matching preflight cannot prevent concurrent inserts from two devices, identify a renamed/rescheduled generic event as belonging to this Trip, or distinguish two intentionally identical events. There is no server-enforced Trip/event link. iPhone has those same limitations.

The iPad adds conservative local recovery: persist the exact payload before creating; persist the returned event ID after success. A reopened screen checks an uncertain request rather than issuing another create. If no match is visible after an uncertain response, it remains read-only and asks the user to check Calendar; it cannot safely conclude the write failed. A confirmed local receipt avoids another insert on this device even if the Calendar event is subsequently edited/deleted. It does not automatically recreate deleted events. These local receipts are recovery aids, not shared backend associations or proof of global uniqueness.

Global atomic uniqueness would require a separately designed backend change, but that stronger guarantee is not a prerequisite for this fix. No new RPC is proposed or required here.

## Files changed for this fix

- `Homey/Features/Trips/TripQuickPlan.swift`: restore opt-in, create Calendar after canonical planning, partial errors, retry/reconciliation and refresh/dismiss.
- `Homey/Features/Trips/TripsView.swift`: wire planned Trip detail action to actual Calendar creation and refresh.
- `Homey/Features/Trips/TripIdeaPlanningAttempt.swift`: backward-compatible Calendar choice/timezone and canonical Trip receipt for recovery.
- `Homey/Features/Trips/TripCalendarPreparation.swift`: normalized live payload, optional notes, validation of paired times; remove unavailable-backend message.
- New `Homey/Features/Trips/TripCalendarService.swift`: adapter to existing Calendar service and iPhone-style matching.
- New `Homey/Features/Trips/TripCalendarSubmission.swift`: in-flight guard, confirmed/uncertain response handling and recovery.
- `Tests/TripsHubChecks.swift`, new `Tests/TripCalendarSubmissionChecks.swift`, `Tests/check-trips-hub-contracts.py`, `Tests/run-trips-hub-checks.sh`: regression coverage.

Meals and Calendar feature sources were not changed.

## Verification and remaining manual checks

`zsh Tests/run-trips-hub-checks.sh` passes standalone Swift behavior tests and source-contract checks. Coverage includes sorting, payload scoping, durable planning UUID/confirmed Trip recovery, Calendar choice/timezone persistence, legacy journals, multi-day all-day DST boundaries, timed ranges, exact Calendar payload, existing-event skip, repeated and simultaneous taps, lost-response reconciliation, relaunch recovery, failed preflight/retry, and Home/account scoping. The unchecked branch and refresh hooks are source-contract checks; Calendar network tests use an injected fake service rather than a live Supabase account.

Simulator SDK build passes with:

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Homey.xcodeproj -scheme Homey -sdk iphonesimulator -derivedDataPath /tmp/HomeyTripsDerived CODE_SIGNING_ALLOWED=NO build`

No live backend writes or authenticated iPhone/iPad cross-device tests were performed. Manual verification:

1. Plan with Calendar checked: one new canonical Trip and one Calendar event; sheets close. Check event in both apps under the same Home.
2. Uncheck Calendar: new Trip, no Calendar event.
3. Plan a multi-day all-day Trip, including Oct 31–Nov 1, 2026 in America/Los_Angeles: event covers both days and ends Nov 2 at midnight (49 elapsed hours).
4. Enable Add Times: selected start/end times appear in Calendar in the Home timezone. Test a device timezone different from the Home timezone.
5. Interrupt networking after planning: Planned Trip remains. Retry Calendar only; never another planning request. For an uncertain create, Check Calendar must not resend an insert.
6. Rapidly tap Plan/Calendar; close/reopen/relaunch after lost responses. Confirm active-session create guard and original request recovery. If the event already exists, no extra insert.
7. Switch Home during each async phase: no old-Home result displayed in the new Home and no writes redirected to it.
8. Use Add to Calendar in Planned Details: actual Calendar event creation, then button reads Added to Calendar.
9. Verify Meals planner and Calendar create/edit flows still work. Calendar and Trips must reload after a successful addition.
