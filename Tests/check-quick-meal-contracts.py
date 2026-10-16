from pathlib import Path
root = Path(__file__).resolve().parents[1]
def read(path):
    return (root / 'Homey/Features/Meals' / path).read_text()
views = read('Views/QuickMealViews.swift')
planner = read('Views/MealPlannerView.swift')
vm = read('Services/MealPlannerViewModel.swift')
service = read('Services/QuickMealService.swift')
route = read('Models/MealSlotAddRoute.swift')
hub = read('Views/MealsHomeHubView.swift')
assert '"Quick Add" : "Recipes"' in route
assert 'Menu {' in views and 'ForEach(MealSlotAddKind.allCases)' in views
assert '.menuOrder(.fixed)' in views
assert 'QuickMealAddChoice' not in views + planner
assert planner.count('MealPlannerAddSheet(route:') == 2
assert planner.count('MealPlannerPickerView(') == 2  # Auto Plan and shared recipe add sheet
assert '.sheet(item: $pendingSelection)' not in planner  # confirmation stays in original host
assert 'route.kind == .quickAdd' in planner and 'route.kind == .quickAdd' in hub
assert 'QuickMealEditor(viewModel: quickPlanner' in hub
assert 'HomeMealPicker(mealType: route.mealType' in hub
assert hub.count('MealSlotAddMenu(onSelect:') == 2  # active hub header and empty-card shortcuts
assert 'pickerContext' not in hub
assert 'MealSlotAddRoute.present(&addRoute' in hub
assert 'route.homeID' in hub and 'viewModel.selectedDate == route.date' in hub
assert 'QuickMealRows(viewModel: quickPlanner' in hub
assert 'if route.kind == .quickAdd' in planner and 'preselectedMealType: route.mealType' in planner
assert 'selection = MealPlannerPendingSelection' in planner
assert 'MealSlotAddMenu(onSelect:' in planner.split('private var listView:')[1].split('private var summaryBar:')[0]
assert 'Button("Cancel", action: onDismiss)' in views
assert 'guard !isSubmitting' in views and '.interactiveDismissDisabled(isSubmitting)' in views
assert 'guard !isSaving else' in vm and 'activeHomeId == homeID' in vm
assert 'normalizedTitle(title)' in views and 'normalizedTitle(title)' in vm
assert 'requestID = entry.id' in views and 'id: requestID' in views
assert 'Edit / Reschedule' in views and 'removeQuickMeal' in views
assert 'canRemovePlannedMeals' in vm and 'canPlanMeals' in vm
assert 'quickMealTitle: quickMeals.first' in read('Services/AutoPlanEngine.swift')
assert 'quickMeals: quickMeals)' in vm and 'if quickEntries.contains' in vm
assert '.from("meals")' not in service and 'meal_event_details' not in service
assert 'createEvent' not in service  # atomic RPC owns exactly one shared event
assert 'createPlannedMeal(' in vm  # original recipe persistence retained
print('Quick Add source contracts passed (runtime UI/backend checks still required)')
meal_service = read('Services/MealService.swift')
settings = (root / 'Homey/Features/MainApp/Views/HomeSettingsView.swift').read_text()
assert '.rpc("clear_home_meals_v2"' in meal_service
assert '.rpc("clear_home_meals"' not in meal_service
clear = meal_service.split('func clearHomeMeals(')[1].split('func searchMeals(')[0]
assert 'guard currentRole == .owner' in clear
assert 'meal_plan_entries_deleted' in read('Models/ClearHomeMealsResult.swift')
assert 'quick_meals_deleted' in read('Models/ClearHomeMealsResult.swift')
assert 'clearMealsHome' in settings and 'Quick Adds, and their meal calendar entries' in settings
settings_clear = settings.split('private func clearMeals()')[1].split('private func clearTrips()')[0]
assert 'isCurrentUserOwner' in settings_clear and 'selectedHome?.id == home.id' in settings_clear
assert '.homeyMealsDidChange' in settings_clear and '.homeyCalendarEventsDidChange' in settings_clear
assert 'quickMealLoadError == nil ?' not in vm  # fail closed if occupancy cannot be fetched
assert 'loadRevision == revision' in vm
assert '$0.homeID == homeID && $0.plannedDate >= start && $0.plannedDate < end' in service
assert 'validateExisting(existingEntry' in vm and 'calendarReconciliation' in service
assert 'existingEntry: entry' in views and 'didInitialize' in views
assert 'await reload()' in vm.split('func removeQuickMeal(')[1].split('func addMeal(')[0]
assert 'CalendarService' not in views  # saves/deletes delegate atomic mutations to RPCs
assert 'leftover' not in service.lower() and 'ingredient' not in service.lower()
print('Clear Meals V2, Home-switch, stale-event, refresh and fail-closed Auto Plan source contracts passed')
assert 'quickAddsOnly: true' in hub
assert 'async let quickLoad: Void = loadQuickMealChannel' in vm
assert 'async let recipeLoad: Void = loadRecipeMealChannel' in vm
assert 'case .success(let entries): quickMeals =' in vm
assert 'case .success(let meals): plannedMeals =' in vm
assert 'Retry Quick Adds' in hub and 'retryQuickMeals()' in hub
assert 'get_quick_meal_plan_entries", error: error' in service
assert 'postgrestCode:' in service
recipe_service = read('Services/MealPlannerService.swift')
assert '.in("calendar_event_id", values:' in recipe_service
assert '.not("meal_id", operator: .is, value: "null")' in recipe_service
assert 'plannedMeals.isEmpty && viewModel.quickMeals.isEmpty' in planner
print('Independent Quick Add/recipe loading, scoped recipe queries and retry source contracts passed')
