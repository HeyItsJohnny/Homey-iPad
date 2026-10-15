from pathlib import Path
root = Path(__file__).resolve().parents[1]
feature = root / 'Homey/Features/Trips'
plan = (feature / 'TripQuickPlan.swift').read_text()
service = (feature / 'Trips2Service.swift').read_text()
view = (feature / 'TripsView.swift').read_text()
assert '@State private var includesTimes = false' in plan
assert 'includesEnd' not in plan and 'Set End Date' not in plan
assert 'TripDateField("End Date", selection: $end, in: start...' in plan
assert 'Toggle("Add to Calendar", isOn: $addToCalendar)' in plan
assert plan.index('try store.confirm(request, tripID: tripID)') < plan.index('await syncCalendar(tripID: tripID, request: request)')
assert 'if request.addToCalendar == true' in plan
retry = plan[plan.index('private func retryCalendar()'):plan.index('private func keepTripOnly()')]
assert 'planIdea(' not in retry
assert '.disabled(saving || calendarSubmission.isSaving || homes.selectedHomeID != homeID)' in plan
assert 'Add to Calendar' in view and 'await addToCalendar()' in view
assert plan.index('try store.save(request)') < plan.index('Trips2Service().planIdea(request)')
assert plan.index('finished = true') < plan.index('await onChanged()')
calendar_adapter = (feature / 'TripCalendarService.swift').read_text()
assert 'calendar.createEvent(homeId: draft.homeID, title: draft.title' in calendar_adapter
assert 'isAllDay: draft.isAllDay, timezone: draft.timezone, categoryId: nil' in calendar_adapter
assert '.homeyCalendarEventsDidChange' in plan and '.homeyCalendarEventsDidChange' in view
assert 'calendarBlocked' not in plan
assert '@State private var addToCalendar = true' in plan
assert '.eq("home_id", value: homeID.uuidString).eq("id", value: ideaID.uuidString)' in service
assert 'seen.insert($0.id).inserted' in service
assert 'organizerHomeID ==' not in service
assert view.count('column("') == 3 and 'ScrollView { LazyVStack' in view
assert 'homes.selectedHomeID != homeID' in view
print('PASS: Always-visible end date, Calendar opt-in and canonical receipt before preparation, persistence before RPC, existing Calendar create API and refresh, scoped mutations, canonical deduplication, three independent scrolling columns')
