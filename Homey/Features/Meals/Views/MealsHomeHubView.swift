import SwiftUI

struct MealsHomeHubView: View {
    @EnvironmentObject private var homeService: HomeService
    @Environment(\.homePermissions) private var permissions
    @StateObject private var viewModel = MealsHomeHubViewModel()
    @StateObject private var quickPlanner = MealPlannerViewModel()
    @State private var addRoute: MealSlotAddRoute?

    private var homeID: UUID? { homeService.selectedHomeID }
    private var timezoneIdentifier: String {
        homeService.selectedHome()?.timezone ?? TimeZone.autoupdatingCurrent.identifier
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            GeometryReader { proxy in
                ScrollView(.vertical) {
                    plannerSurface
                        .frame(height: proxy.size.height)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await viewModel.refreshMealPlanner()
                    await quickPlanner.reload()
                }
            }
        }
        .padding(.horizontal, 34)
        .padding(.top, 34)
        .padding(.bottom, 38)
        .frame(maxWidth: 1180, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .center)
        .task(id: "\(homeID?.uuidString ?? "no-home"):\(timezoneIdentifier)") {
            await viewModel.configure(homeID: homeID, timezoneIdentifier: timezoneIdentifier)
        }
        .task(id: "\(homeID?.uuidString ?? "no-home"):\(timezoneIdentifier):\(viewModel.selectedDate.timeIntervalSince1970)") {
            addRoute = nil
            quickPlanner.load(homeId: homeID, weekStartsOn: nil, timezone: timezoneIdentifier,
                selectedDay: viewModel.selectedDate, quickAddsOnly: true)
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .homeyCalendarEventsDidChange) {
                await viewModel.refreshMealPlanner()
            }
        }
        .sheet(item: $addRoute) { route in
            if route.kind == .quickAdd {
                QuickMealEditor(viewModel: quickPlanner, homeID: route.homeID, date: route.date,
                    mealType: route.mealType, permissions: permissions, onDismiss: { addRoute = nil })
            } else {
                HomeMealPicker(mealType: route.mealType, meals: viewModel.homeMeals,
                    isSaving: viewModel.isSaving) { meal in
                    guard homeID == route.homeID, viewModel.selectedDate == route.date else { return false }
                    return await viewModel.addMeal(meal, to: route.mealType)
                }
                .presentationDetents([.large])
            }
        }
        .alert("Meal Planner", isPresented: Binding(
            get: { quickPlanner.errorMessage != nil },
            set: { if !$0 { quickPlanner.errorMessage = nil } })) {
            Button("OK") { quickPlanner.errorMessage = nil }
        } message: { Text(quickPlanner.errorMessage ?? "") }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Meals")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("What's on the menu today?")
                    .font(.title3)
                    .foregroundStyle(HomeyTheme.textSecondary)
            }

            Spacer()

            HStack(spacing: 10) {
                todayButton
                dateNavigator
            }
                .padding(.trailing, 70)
        }
    }

    private var todayButton: some View {
        Button {
            Task { await viewModel.returnToToday() }
        } label: {
            Text("Today")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyTheme.primary)
                .frame(minHeight: 44)
                .padding(.horizontal, 16)
                .background(HomeyTheme.surfacePrimary, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(HomeyTheme.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Go to today")
    }

    private var dateNavigator: some View {
        HStack(spacing: 7) {
            dateArrow(systemImage: "chevron.left", label: "Previous day") {
                await viewModel.moveSelectedDate(by: -1)
            }

            HStack(spacing: 7) {
                Image(systemName: "calendar")
                    .font(.subheadline.weight(.bold))
                Text(viewModel.selectedDateLabel)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(HomeyTheme.primary)
            .padding(.horizontal, 13)
            .frame(minHeight: 38)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(viewModel.selectedDateLabel)

            dateArrow(systemImage: "chevron.right", label: "Next day") {
                await viewModel.moveSelectedDate(by: 1)
            }
        }
        .padding(5)
        .background(HomeyTheme.surfacePrimary, in: Capsule())
        .overlay {
            Capsule().stroke(HomeyTheme.borderSubtle, lineWidth: 1)
        }
        .shadow(color: HomeyTheme.shadow, radius: 10, x: 0, y: 5)
    }

    private func dateArrow(
        systemImage: String,
        label: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyTheme.primary)
                .frame(width: 36, height: 36)
                .background(HomeyTheme.primary.opacity(0.09), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
        .accessibilityLabel(label)
    }

    private var plannerSurface: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let errorMessage = viewModel.errorMessage {
                HStack(spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(errorMessage)
                    Spacer()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyTheme.danger)
                .padding(12)
                .background(
                    HomeyTheme.danger.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
                )
            }

            if let message = quickPlanner.quickMealLoadError {
                HStack {
                    Text(message).font(.footnote).foregroundStyle(HomeyTheme.textSecondary)
                    Button("Retry Quick Adds") { Task { await quickPlanner.retryQuickMeals() } }
                        .disabled(quickPlanner.isLoadingQuickMeals)
                }
            }
            HStack(alignment: .top, spacing: 16) {
                ForEach(MealsHomeHubViewModel.visibleMealTypes) { mealType in
                    mealSection(mealType)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .overlay {
                if viewModel.isLoading && viewModel.itemsByType.isEmpty && quickPlanner.quickMeals.isEmpty {
                    ProgressView("Loading meal plan…")
                        .tint(HomeyTheme.primary)
                        .padding(20)
                        .background(HomeyTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: HomeyRadius.card, style: .continuous))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardCard(cornerRadius: HomeyRadius.page)
    }

    private func mealSection(_ mealType: MealType) -> some View {
        let items = viewModel.items(for: mealType)
        let quickEntries = quickPlanner.quickMeals(on: viewModel.selectedDate, mealType: mealType)

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: mealType.systemImageName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(sectionColor(mealType))

                VStack(alignment: .leading, spacing: 2) {
                    Text(sectionTitle(mealType))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(HomeyTheme.textPrimary)
                    Text("\(items.count + quickEntries.count) planned")
                        .font(.caption)
                        .foregroundStyle(HomeyTheme.textSecondary)
                }

                Spacer(minLength: 4)

                MealSlotAddMenu(onSelect: { kind in presentAdd(mealType, kind: kind) }) {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(HomeyTheme.primary)
                        .frame(width: 34, height: 34)
                        .background(HomeyTheme.surfacePrimary, in: Circle())
                        .overlay { Circle().stroke(HomeyTheme.borderSubtle, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .disabled(!permissions.meals.canPlanMeals || viewModel.isSaving || quickPlanner.isSaving || addRoute != nil)
                .accessibilityLabel("Add \(sectionTitle(mealType)) meal")
            }
            .padding(14)
            .background(sectionColor(mealType).opacity(0.10))

            ScrollView {
                LazyVStack(spacing: 10) {
                    QuickMealRows(viewModel: quickPlanner, entries: quickEntries, permissions: permissions)
                    if items.isEmpty && quickEntries.isEmpty {
                        emptyState(mealType)
                    } else {
                        ForEach(items) { item in
                            plannedMealCard(item)
                        }
                    }
                }
                .padding(12)
            }
            .scrollIndicators(.visible)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(HomeyTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: HomeyRadius.card, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: HomeyRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HomeyRadius.card, style: .continuous)
                .stroke(HomeyTheme.borderSubtle.opacity(0.75), lineWidth: 1)
        }
    }

    private func plannedMealCard(_ item: MealPlanItem) -> some View {
        HStack(spacing: 11) {
            MealPhotoThumbnail(path: item.meal.primaryPhotoPath)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: HomeyRadius.control, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.meal.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyTheme.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if item.entry.isLeftover {
                    Label("Leftover", systemImage: "arrow.uturn.forward.circle.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(HomeyTheme.success)
                }
            }

            if viewModel.isDeleting(item) {
                ProgressView()
                    .controlSize(.small)
                    .tint(HomeyTheme.primary)
            } else if permissions.meals.canPlanMeals {
                Menu {
                    Button("Remove", systemImage: "calendar.badge.minus", role: .destructive) {
                        Task { await viewModel.removeMeal(item) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title3)
                        .foregroundStyle(HomeyTheme.textSecondary)
                        .frame(width: 36, height: 44)
                }
                .accessibilityLabel("Actions for \(item.meal.name)")
            }
        }
        .padding(10)
        .background(HomeyTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
                .stroke(HomeyTheme.borderSubtle.opacity(0.65), lineWidth: 1)
        }
    }

    private func emptyState(_ mealType: MealType) -> some View {
        VStack(spacing: 10) {
            Image(systemName: mealType.systemImageName)
                .font(.title2)
                .foregroundStyle(sectionColor(mealType))
            Text("No \(sectionTitle(mealType).lowercased()) planned")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyTheme.textSecondary)
            if permissions.meals.canPlanMeals {
                MealSlotAddMenu(onSelect: { kind in presentAdd(mealType, kind: kind) }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(HomeyTheme.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(sectionTitle(mealType)) meal")
            }
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }

    private func presentAdd(_ mealType: MealType, kind: MealSlotAddKind) {
        guard permissions.meals.canPlanMeals, !viewModel.isSaving, !quickPlanner.isSaving else { return }
        MealSlotAddRoute.present(&addRoute, homeID: homeID, date: viewModel.selectedDate,
            mealType: mealType, kind: kind)
    }

    private func sectionColor(_ mealType: MealType) -> Color {
        switch mealType {
        case .breakfast:
            return HomeyTheme.mealBreakfast
        case .lunch:
            return HomeyTheme.mealLunch
        case .dinner:
            return HomeyTheme.mealDinner
        case .snack, .dessert, .drink:
            return HomeyTheme.mealSnack
        }
    }

    private func sectionTitle(_ mealType: MealType) -> String {
        mealType == .snack ? "Snacks" : mealType.displayName
    }
}

private struct HomeMealPicker: View {
    @Environment(\.dismiss) private var dismiss
    let mealType: MealType
    let meals: [Meal]
    let isSaving: Bool
    let onSelect: (Meal) async -> Bool

    @State private var searchText = ""
    @State private var selectedMealID: UUID?
    @State private var errorMessage: String?

    private var matchingMeals: [Meal] {
        meals.filter { $0.mealTypes.contains(mealType) }
    }

    private var filteredMeals: [Meal] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return matchingMeals }
        return matchingMeals.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.description?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if matchingMeals.isEmpty {
                    ContentUnavailableView(
                        "No \(mealType.displayName) Recipes Yet",
                        systemImage: "fork.knife",
                        description: Text("Recipes tagged \(mealType.displayName) will appear here when they are available.")
                    )
                } else if filteredMeals.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredMeals) { meal in
                                Button {
                                    add(meal)
                                } label: {
                                    HStack(spacing: 13) {
                                        MealPhotoThumbnail(path: meal.primaryPhotoPath)
                                            .frame(width: 62, height: 62)
                                            .clipShape(RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))

                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(meal.name)
                                                .font(.headline)
                                                .foregroundStyle(HomeyTheme.textPrimary)
                                                .multilineTextAlignment(.leading)
                                            if let description = meal.description, !description.isEmpty {
                                                Text(description)
                                                    .font(.caption)
                                                    .foregroundStyle(HomeyTheme.textSecondary)
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.leading)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                        if selectedMealID == meal.id || (isSaving && selectedMealID == meal.id) {
                                            ProgressView()
                                                .tint(HomeyTheme.primary)
                                        } else {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.title2)
                                                .foregroundStyle(HomeyTheme.primary)
                                        }
                                    }
                                    .padding(11)
                                    .background(HomeyTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: HomeyRadius.card, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: HomeyRadius.card, style: .continuous)
                                            .stroke(HomeyTheme.borderSubtle, lineWidth: 1)
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(selectedMealID != nil || isSaving)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .background(HomeyTheme.backgroundPrimary)
            .navigationTitle("Choose \(mealType == .snack ? "Snacks" : mealType.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search Home Meals")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeyTheme.danger)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(HomeyTheme.surfacePrimary)
                }
            }
        }
    }

    private func add(_ meal: Meal) {
        guard selectedMealID == nil else { return }
        selectedMealID = meal.id
        errorMessage = nil
        Task {
            if await onSelect(meal) {
                dismiss()
            } else {
                selectedMealID = nil
                errorMessage = "That meal couldn't be added. Please try again."
            }
        }
    }
}
