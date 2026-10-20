import SwiftUI

struct HomeSettingsView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService

    var onClose: () -> Void = {}
    var onShowCalendarCategories: () -> Void = {}

    @State private var clearTripsHome: HomeSummary?
    @State private var isShowingClearTripsConfirmation = false
    @State private var clearTripsConfirmationText = ""
    @State private var isClearingTrips = false
    @State private var clearTripsErrorMessage: String?
    @State private var isShowingClearTripsError = false
    @State private var homeName = ""
    @State private var timezone = TimeZone.current.identifier
    @State private var weekStartsOn = WeekStartOption.sunday.rawValue
    @State private var originalValues: HomeSettingsValues?
    @State private var isShowingTimezonePicker = false
    @State private var successMessage: String?
    @State private var errorMessage: String?
    @State private var isShowingSaveError = false
    @State private var isShowingDiscardConfirmation = false
    @State private var isShowingClearChoresDialog = false
    @State private var isShowingClearChoresConfirmation = false
    @State private var isShowingClearChoresError = false
    @State private var clearChoresConfirmationText = ""
    @State private var clearChoresErrorMessage: String?
    @State private var isClearingChores = false
    @State private var clearMealsHome: HomeSummary?
    @State private var isShowingClearMealsDialog = false
    @State private var isShowingClearMealsConfirmation = false
    @State private var isShowingClearMealsError = false
    @State private var clearMealsConfirmationText = ""
    @State private var clearMealsErrorMessage: String?
    @State private var isClearingMeals = false
    @State private var isShowingClearCalendarDialog = false
    @State private var isShowingClearCalendarConfirmation = false
    @State private var isShowingClearCalendarError = false
    @State private var clearCalendarConfirmationText = ""
    @State private var clearCalendarErrorMessage: String?
    @State private var isClearingCalendar = false

    private let choresRepository = ChoresRepository()
    private let mealService = MealService()
    private let calendarService = CalendarService()

    private var selectedHome: HomeSummary? {
        homeService.selectedHome()
    }

    private var trimmedHomeName: String {
        homeName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentValues: HomeSettingsValues {
        HomeSettingsValues(
            name: trimmedHomeName,
            timezone: timezone,
            weekStartsOn: weekStartsOn
        )
    }

    private var hasUnsavedChanges: Bool {
        guard let originalValues else {
            return false
        }

        return currentValues != originalValues
    }

    private var canSave: Bool {
        hasUnsavedChanges && !trimmedHomeName.isEmpty && !homeService.isLoading
    }

    private var isCurrentUserOwner: Bool {
        homeService.selectedHomeRole(currentUserID: authenticationService.currentUser?.id) == .owner
    }

    var body: some View {
        ZStack {
            HomeyTheme.backgroundPrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    if selectedHome == nil {
                        missingHomeState
                    } else {
                        settingsContent
                    }
                }
                .padding(.horizontal, 34)
                .padding(.top, 34)
                .padding(.bottom, 38)
                .frame(maxWidth: 920, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
        .task(id: selectedHome?.id) {
            loadSelectedHome()
        }
        .sheet(isPresented: $isShowingTimezonePicker) {
            TimeZonePickerView(selectedTimezone: $timezone)
        }
        .sheet(isPresented: $isShowingClearTripsConfirmation) {
            if let home = clearTripsHome {
                ClearHomeDataConfirmationSheet(
                    title: "Clear Trips?", homeName: home.name, message: TripsResetNotice.confirmation,
                    confirmButtonTitle: "Clear Trips", loadingAccessibilityLabel: "Clearing Trips",
                    confirmationText: $clearTripsConfirmationText, isClearing: isClearingTrips,
                    onCancel: { if !isClearingTrips { isShowingClearTripsConfirmation = false } },
                    onConfirm: { Task { await clearTrips() } }
                )
            }
        }
        .alert("Unable to Clear Trips", isPresented: $isShowingClearTripsError) {
            Button("OK", role: .cancel) {}
        } message: { Text(clearTripsErrorMessage ?? "Trips could not be cleared.") }
        .onChange(of: selectedHome?.id) { _, _ in
            isShowingClearMealsDialog = false
            isShowingClearMealsConfirmation = false
            clearMealsConfirmationText = ""
            clearMealsHome = nil
            clearMealsErrorMessage = nil
            isShowingClearMealsError = false
            isShowingClearTripsConfirmation = false
            clearTripsConfirmationText = ""
            clearTripsErrorMessage = nil
            isShowingClearTripsError = false
        }
        .onChange(of: isCurrentUserOwner) { _, owner in
            if !owner {
                isShowingClearTripsConfirmation = false
                isShowingClearMealsDialog = false
                isShowingClearMealsConfirmation = false
            }
        }
        .alert("Unable to Save Changes", isPresented: $isShowingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
        .confirmationDialog(
            "Discard Changes?",
            isPresented: $isShowingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard Changes", role: .destructive) {
                onClose()
            }
        } message: {
            Text("Your changes have not been saved.")
        }
        .confirmationDialog(
            "Clear Chores & Tasks?",
            isPresented: $isShowingClearChoresDialog,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Chores & Tasks", role: .destructive) {
                clearChoresConfirmationText = ""
                isShowingClearChoresConfirmation = true
            }
        } message: {
            Text("This will permanently delete all chores, daily tasks, assignments, completions, approvals, reward activity, and related points for this Home. This cannot be undone.")
        }
        .sheet(isPresented: $isShowingClearChoresConfirmation) {
            ClearHomeDataConfirmationSheet(
                title: "Clear Chores & Tasks?",
                homeName: selectedHome?.name ?? "this Home",
                message: "This will permanently delete all chores, daily tasks, assignments, completions, approvals, reward activity, and related points for this Home. This cannot be undone.",
                confirmButtonTitle: "Clear Chores & Tasks",
                loadingAccessibilityLabel: "Clearing chores and tasks",
                confirmationText: $clearChoresConfirmationText,
                isClearing: isClearingChores,
                onCancel: {
                    guard !isClearingChores else { return }
                    isShowingClearChoresConfirmation = false
                },
                onConfirm: {
                    Task {
                        await clearChores()
                    }
                }
            )
        }
        .alert("Unable to Clear Chores & Tasks", isPresented: $isShowingClearChoresError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(clearChoresErrorMessage ?? "Please try again.")
        }
        .confirmationDialog(
            "Clear Meals?",
            isPresented: $isShowingClearMealsDialog,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Meals", role: .destructive) {
                clearMealsConfirmationText = ""
                isShowingClearMealsConfirmation = true
            }
        } message: {
            Text("This will permanently delete this Home's recipes, meal plans, Quick Adds, and their meal calendar entries. Explore and Community Recipes will not be deleted.")
        }
        .sheet(isPresented: $isShowingClearMealsConfirmation) {
            ClearHomeDataConfirmationSheet(
                title: "Clear Meals?",
                homeName: clearMealsHome?.name ?? "this Home",
                message: "This will permanently delete this Home's recipes, meal plans, Quick Adds, and their meal calendar entries. Explore and Community Recipes will not be deleted. This cannot be undone.",
                confirmButtonTitle: "Clear Meals",
                loadingAccessibilityLabel: "Clearing meals",
                confirmationText: $clearMealsConfirmationText,
                isClearing: isClearingMeals,
                onCancel: {
                    guard !isClearingMeals else { return }
                    isShowingClearMealsConfirmation = false
                },
                onConfirm: {
                    Task {
                        await clearMeals()
                    }
                }
            )
        }
        .alert("Unable to Clear Meals", isPresented: $isShowingClearMealsError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(clearMealsErrorMessage ?? "Please try again.")
        }
        .confirmationDialog(
            "Clear Calendar?",
            isPresented: $isShowingClearCalendarDialog,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Calendar", role: .destructive) {
                clearCalendarConfirmationText = ""
                isShowingClearCalendarConfirmation = true
            }
        } message: {
            Text("This will permanently delete this Home's calendar events. Meal plans, recipes, chores, rewards, and Global Recipes will not be deleted.")
        }
        .sheet(isPresented: $isShowingClearCalendarConfirmation) {
            ClearHomeDataConfirmationSheet(
                title: "Clear Calendar?",
                homeName: selectedHome?.name ?? "this Home",
                message: "This will permanently delete this Home's calendar events. Meal plans, recipes, chores, rewards, and Global Recipes will not be deleted. This cannot be undone.",
                confirmButtonTitle: "Clear Calendar",
                loadingAccessibilityLabel: "Clearing calendar",
                confirmationText: $clearCalendarConfirmationText,
                isClearing: isClearingCalendar,
                onCancel: {
                    guard !isClearingCalendar else { return }
                    isShowingClearCalendarConfirmation = false
                },
                onConfirm: {
                    Task {
                        await clearCalendar()
                    }
                }
            )
        }
        .alert("Unable to Clear Calendar", isPresented: $isShowingClearCalendarError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(clearCalendarErrorMessage ?? "Please try again.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Home Settings")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyTheme.textPrimary)

                Text("Manage the basic details and preferences for your home.")
                    .font(.title3)
                    .foregroundStyle(HomeyTheme.textSecondary)
            }

            Spacer()

            Button {
                closeOrConfirmDiscard()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
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
        }
    }

    private var missingHomeState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unable to load Home Settings.")
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyTheme.textPrimary)

            Text("Please choose a Home and try again.")
                .font(.body)
                .foregroundStyle(HomeyTheme.textSecondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard(cornerRadius: HomeyRadius.page)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 18) {
                DashboardSettingsTextField(
                    label: "Home Name",
                    supportingText: "This name is shown to everyone in your home.",
                    text: $homeName
                )

                DashboardSettingsPickerButton(
                    label: "Time Zone",
                    supportingText: "Used for calendars, chores, meals, reminders, and notifications.",
                    value: timezoneDisplayName(for: timezone),
                    accessibilityLabel: "Time Zone selector"
                ) {
                    isShowingTimezonePicker = true
                }

                DashboardWeekStartPicker(selection: $weekStartsOn)

                DashboardSettingsNavigationRow(
                    title: "Calendar Categories",
                    supportingText: "Manage the shared colors and icons used for events.",
                    systemImage: "tag.fill",
                    action: onShowCalendarCategories
                )
            }

            if let successMessage {
                DashboardSettingsSuccessBanner(message: successMessage)
                    .transition(.opacity)
            }

            if trimmedHomeName.isEmpty && hasUnsavedChanges {
                DashboardSettingsErrorBanner(message: "Home name is required.")
            }

            Button {
                Task {
                    await saveChanges()
                }
            } label: {
                if homeService.isLoading {
                    ProgressView()
                        .tint(.white)
                        .accessibilityLabel("Saving changes")
                } else {
                    Text("Save Changes")
                }
            }
            .buttonStyle(HomeyPrimaryButtonStyle())
            .disabled(!canSave)
            .accessibilityLabel("Save Changes")
        }
        .padding(28)
        .dashboardCard(cornerRadius: HomeyRadius.page)
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsCard

            if UIDevice.current.userInterfaceIdiom == .phone && isCurrentUserOwner {
                dangerZoneCard
            }
        }
    }

    private var dangerZoneCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Danger Zone")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyTheme.danger)

                Text("These actions permanently clear data for this Home. Each action has its own confirmation.")
                    .font(.subheadline)
                    .foregroundStyle(HomeyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            dangerZoneAction(
                title: "Clear Chores & Tasks",
                description: "Deletes all chores, daily tasks, assignments, completions, approvals, reward activity, and related points for this Home.",
                systemImage: "trash.fill",
                isLoading: isClearingChores,
                loadingTitle: "Clearing Chores & Tasks...",
                action: { isShowingClearChoresDialog = true }
            )

            Divider()
                .overlay(HomeyTheme.danger.opacity(0.18))

            dangerZoneAction(
                title: "Clear Meals",
                description: "Deletes this Home's meal plans, Quick Adds, Home Recipes, and Home-specific meal data. Explore and Community Recipes are not deleted.",
                systemImage: "fork.knife",
                isLoading: isClearingMeals,
                loadingTitle: "Clearing Meals...",
                action: {
                    guard let home = selectedHome, isCurrentUserOwner else { return }
                    clearMealsHome = home
                    isShowingClearMealsDialog = true
                }
            )

            Divider()
                .overlay(HomeyTheme.danger.opacity(0.18))

            dangerZoneAction(
                title: "Clear Calendar",
                description: "Deletes regular calendar events belonging to this Home. Meal plans and chores are not deleted.",
                systemImage: "calendar.badge.minus",
                isLoading: isClearingCalendar,
                loadingTitle: "Clearing Calendar...",
                action: { isShowingClearCalendarDialog = true }
            )
            Divider().overlay(HomeyTheme.danger.opacity(0.18))
            dangerZoneAction(
                title: "Clear Trips",
                description: "Deletes organized Trips and removes this Home from other households’ Trips. Calendar events remain.",
                systemImage: "airplane", isLoading: isClearingTrips, loadingTitle: "Clearing Trips...",
                action: {
                    guard isCurrentUserOwner, !isClearingTrips, let home = selectedHome else { return }
                    clearTripsHome = home
                    clearTripsConfirmationText = ""
                    isShowingClearTripsConfirmation = true
                }
            )
        }
        .disabled(isClearingTrips)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: HomeyRadius.page, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HomeyRadius.page, style: .continuous)
                .stroke(HomeyTheme.danger.opacity(0.28), lineWidth: 1)
        }
    }

    private func dangerZoneAction(
        title: String,
        description: String,
        systemImage: String,
        isLoading: Bool,
        loadingTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyTheme.textPrimary)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(HomeyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: action) {
                HStack(spacing: 10) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.small)
                    } else {
                        Image(systemName: systemImage)
                            .accessibilityHidden(true)
                    }

                    Text(isLoading ? loadingTitle : title)
                }
            }
            .buttonStyle(DashboardDestructiveButtonStyle())
            .disabled(isLoading)
            .accessibilityLabel(title)
        }
    }

    // MARK: - Actions

    private func loadSelectedHome() {
        guard let selectedHome else {
            return
        }

        let loadedValues = HomeSettingsValues(
            name: selectedHome.name,
            timezone: selectedHome.timezone ?? TimeZone.current.identifier,
            weekStartsOn: WeekStartOption(rawValue: selectedHome.weekStartsOn)?.rawValue ?? WeekStartOption.sunday.rawValue
        )

        homeName = loadedValues.name
        timezone = loadedValues.timezone
        weekStartsOn = loadedValues.weekStartsOn
        originalValues = loadedValues
        successMessage = nil
        errorMessage = nil
    }

    private func saveChanges() async {
        guard canSave else {
            return
        }

        guard let selectedHome else {
            errorMessage = "Unable to load Home Settings. Please choose a Home and try again."
            isShowingSaveError = true
            return
        }

        guard let userID = authenticationService.currentUser?.id else {
            errorMessage = "Unable to identify the current user."
            isShowingSaveError = true
            return
        }

        successMessage = nil
        let didSave = await homeService.updateHomeSettings(
            homeID: selectedHome.id,
            name: homeName,
            timezone: timezone,
            weekStartsOn: weekStartsOn,
            userID: userID
        )

        if didSave {
            let savedValues = currentValues
            homeName = savedValues.name
            originalValues = savedValues

            withAnimation(.easeInOut(duration: 0.2)) {
                successMessage = "Changes saved"
            }
        } else {
            errorMessage = homeService.errorMessage ?? "Unable to save Home settings."
            isShowingSaveError = true
        }
    }

    private func clearChores() async {
        guard !isClearingChores else {
            return
        }

        guard clearChoresConfirmationText == "CLEAR" else {
            return
        }

        guard let selectedHome else {
            clearChoresErrorMessage = "Unable to load Home Settings. Please choose a Home and try again."
            isShowingClearChoresError = true
            return
        }

        isClearingChores = true
        clearChoresErrorMessage = nil
        successMessage = nil
        defer { isClearingChores = false }

        do {
            _ = try await choresRepository.clearHomeChores(
                homeId: selectedHome.id,
                currentRole: homeService.selectedHomeRole(currentUserID: authenticationService.currentUser?.id)
            )
            clearChoresConfirmationText = ""
            isShowingClearChoresConfirmation = false
            NotificationCenter.default.post(name: .homeyChoresDidChange, object: nil)
            NotificationCenter.default.post(name: Notification.Name("homeyDailyTasksDidChange"), object: nil)

            withAnimation(.easeInOut(duration: 0.2)) {
                successMessage = "Chores and Tasks cleared."
            }
        } catch {
            clearChoresErrorMessage = error.localizedDescription
            isShowingClearChoresError = true
        }
    }

    private func clearMeals() async {
        guard !isClearingMeals else {
            return
        }

        guard clearMealsConfirmationText == "CLEAR" else {
            return
        }

        guard let home = clearMealsHome, selectedHome?.id == home.id, isCurrentUserOwner else {
            clearMealsErrorMessage = "Unable to load Home Settings. Please choose a Home and try again."
            isShowingClearMealsError = true
            return
        }

        isClearingMeals = true
        clearMealsErrorMessage = nil
        successMessage = nil
        defer { isClearingMeals = false }

        do {
            _ = try await mealService.clearHomeMeals(
                homeId: home.id,
                currentRole: homeService.selectedHomeRole(currentUserID: authenticationService.currentUser?.id)
            )
            clearMealsConfirmationText = ""
            isShowingClearMealsConfirmation = false
            NotificationCenter.default.post(name: .homeyMealsDidChange, object: nil)
            NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: nil)

            guard selectedHome?.id == home.id else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                successMessage = "Meals and Quick Adds have been cleared for this Home."
            }
        } catch {
            guard selectedHome?.id == home.id else { return }
            clearMealsErrorMessage = error.localizedDescription
            isShowingClearMealsError = true
        }
    }

    private func clearTrips() async {
        guard !isClearingTrips, clearTripsConfirmationText == "CLEAR",
              let home = clearTripsHome, selectedHome?.id == home.id, isCurrentUserOwner else { return }
        isClearingTrips = true
        clearTripsErrorMessage = nil
        successMessage = nil
        defer { isClearingTrips = false }
        do {
            _ = try await HomeTripsResetService().clear(homeID: home.id,
                role: homeService.selectedHomeRole(currentUserID: authenticationService.currentUser?.id))
            NotificationCenter.default.post(name: TripsResetNotice.name, object: home.id)
            guard selectedHome?.id == home.id else { return }
            clearTripsConfirmationText = ""
            isShowingClearTripsConfirmation = false
            successMessage = "Trips cleared."
        } catch is CancellationError {
        } catch {
            guard selectedHome?.id == home.id else { return }
            clearTripsErrorMessage = "Trips could not be cleared."
            isShowingClearTripsError = true
        }
    }

    private func clearCalendar() async {
        guard !isClearingCalendar else {
            return
        }

        guard clearCalendarConfirmationText == "CLEAR" else {
            return
        }

        guard let selectedHome else {
            clearCalendarErrorMessage = "Unable to load Home Settings. Please choose a Home and try again."
            isShowingClearCalendarError = true
            return
        }

        isClearingCalendar = true
        clearCalendarErrorMessage = nil
        successMessage = nil
        defer { isClearingCalendar = false }

        do {
            _ = try await calendarService.clearHomeCalendar(
                homeId: selectedHome.id,
                currentRole: homeService.selectedHomeRole(currentUserID: authenticationService.currentUser?.id)
            )
            clearCalendarConfirmationText = ""
            isShowingClearCalendarConfirmation = false
            NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: nil)

            withAnimation(.easeInOut(duration: 0.2)) {
                successMessage = "Calendar events have been cleared for this Home."
            }
        } catch {
            clearCalendarErrorMessage = error.localizedDescription
            isShowingClearCalendarError = true
        }
    }

    private func closeOrConfirmDiscard() {
        if hasUnsavedChanges {
            isShowingDiscardConfirmation = true
        } else {
            onClose()
        }
    }

    private func timezoneDisplayName(for identifier: String) -> String {
        guard let timeZone = TimeZone(identifier: identifier) else {
            return identifier
        }

        let city = identifier
            .split(separator: "/")
            .last
            .map { String($0).replacingOccurrences(of: "_", with: " ") } ?? identifier
        let offset = timeZone.secondsFromGMT() / 3600
        let offsetText = offset >= 0 ? "GMT+\(offset)" : "GMT\(offset)"
        return "\(city) (\(identifier), \(offsetText))"
    }
}

private struct HomeSettingsValues: Equatable {
    let name: String
    let timezone: String
    let weekStartsOn: Int
}

private enum WeekStartOption: Int, CaseIterable, Identifiable {
    case sunday = 1
    case monday = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .sunday:
            "Sunday"
        case .monday:
            "Monday"
        }
    }
}

private struct DashboardSettingsTextField: View {
    let label: String
    let supportingText: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            settingsLabel(label, supportingText: supportingText)

            TextField(label, text: $text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .font(.body.weight(.medium))
                .foregroundStyle(HomeyTheme.textPrimary)
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .background(HomeyTheme.backgroundPrimary.opacity(0.62), in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
                        .stroke(HomeyTheme.borderSubtle, lineWidth: 1)
                }
                .accessibilityLabel("Home Name field")
        }
    }
}

private struct DashboardSettingsPickerButton: View {
    let label: String
    let supportingText: String
    let value: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            settingsLabel(label, supportingText: supportingText)

            Button(action: action) {
                HStack(spacing: 12) {
                    Text(value)
                        .font(.body.weight(.medium))
                        .foregroundStyle(HomeyTheme.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyTheme.textSecondary)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .background(HomeyTheme.backgroundPrimary.opacity(0.62), in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
                        .stroke(HomeyTheme.borderSubtle, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
        }
    }
}

private struct DashboardSettingsNavigationRow: View {
    let title: String
    let supportingText: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
                        .fill(HomeyTheme.primarySoft)
                        .frame(width: 44, height: 44)

                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HomeyTheme.primary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HomeyTheme.textPrimary)

                    Text(supportingText)
                        .font(.caption)
                        .foregroundStyle(HomeyTheme.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyTheme.textSecondary.opacity(0.72))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(HomeyTheme.backgroundPrimary.opacity(0.62), in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
                    .stroke(HomeyTheme.borderSubtle, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct DashboardWeekStartPicker: View {
    @Binding var selection: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            settingsLabel(
                "Week Starts On",
                supportingText: "Controls how weekly calendars and planners are displayed."
            )

            HStack(spacing: 10) {
                ForEach(WeekStartOption.allCases) { option in
                    Button {
                        selection = option.rawValue
                    } label: {
                        Text(option.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(selection == option.rawValue ? .white : HomeyTheme.primary)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(
                                selection == option.rawValue ? HomeyTheme.primary : HomeyTheme.primarySoft,
                                in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Week Starts On selector")
        }
    }
}

private struct DashboardSettingsSuccessBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(HomeyTheme.success)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyTheme.textPrimary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyTheme.success.opacity(0.14), in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
        .accessibilityLabel(message)
    }
}

private struct DashboardSettingsErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(HomeyTheme.danger)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyTheme.textPrimary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyTheme.danger.opacity(0.10), in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
        .accessibilityLabel(message)
    }
}



private struct DashboardDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                HomeyTheme.danger.opacity(isEnabled ? 1 : 0.38),
                in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
            )
            .shadow(
                color: HomeyTheme.danger.opacity(isEnabled && !configuration.isPressed ? 0.16 : 0.05),
                radius: 12,
                x: 0,
                y: 7
            )
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

private struct ClearHomeDataConfirmationSheet: View {
    let title: String
    let homeName: String
    let message: String
    let confirmButtonTitle: String
    let loadingAccessibilityLabel: String
    @Binding var confirmationText: String
    let isClearing: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var canConfirm: Bool {
        confirmationText == "CLEAR" && !isClearing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(HomeyTheme.danger)
                    .frame(width: 46, height: 46)
                    .background(HomeyTheme.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(HomeyTheme.textPrimary)

                    Text(homeName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeyTheme.textSecondary)
                }
            }

            Text(message)
                .font(.body)
                .foregroundStyle(HomeyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 9) {
                settingsLabel("Type CLEAR to confirm", supportingText: "This reset cannot be undone.")

                TextField("CLEAR", text: $confirmationText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.weight(.bold))
                    .foregroundStyle(HomeyTheme.textPrimary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 54)
                    .background(HomeyTheme.backgroundPrimary.opacity(0.62), in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
                            .stroke(HomeyTheme.borderSubtle, lineWidth: 1)
                    }
                    .disabled(isClearing)
            }

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HomeyTheme.primary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(HomeyTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
                            .stroke(HomeyTheme.borderSubtle, lineWidth: 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(isClearing)

                Button(action: onConfirm) {
                    if isClearing {
                        ProgressView()
                            .tint(.white)
                            .accessibilityLabel(loadingAccessibilityLabel)
                    } else {
                        Text(confirmButtonTitle)
                    }
                }
                .buttonStyle(DashboardDestructiveButtonStyle())
                .disabled(!canConfirm)
            }
        }
        .padding(28)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isClearing)
    }
}

private func settingsLabel(_ title: String, supportingText: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(HomeyTheme.textPrimary)

        Text(supportingText)
            .font(.caption)
            .foregroundStyle(HomeyTheme.textSecondary)
    }
}

private struct TimeZonePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTimezone: String
    @State private var searchText = ""

    private var filteredTimezones: [String] {
        let identifiers = TimeZone.knownTimeZoneIdentifiers.sorted()
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedSearch.isEmpty else {
            return identifiers
        }

        return identifiers.filter { identifier in
            identifier.localizedCaseInsensitiveContains(trimmedSearch)
                || friendlyName(for: identifier).localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredTimezones, id: \.self) { identifier in
                Button {
                    selectedTimezone = identifier
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(friendlyName(for: identifier))
                                .foregroundStyle(HomeyTheme.textPrimary)

                            Text(identifier)
                                .font(.caption)
                                .foregroundStyle(HomeyTheme.textSecondary)
                        }

                        Spacer()

                        if selectedTimezone == identifier {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.bold))
                                .foregroundStyle(HomeyTheme.primary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Time Zone")
            .searchable(text: $searchText, prompt: "Search time zones")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func friendlyName(for identifier: String) -> String {
        identifier
            .split(separator: "/")
            .last
            .map { String($0).replacingOccurrences(of: "_", with: " ") } ?? identifier
    }
}

#Preview("Home Settings") {
    HomeSettingsView()
        .environmentObject(AuthenticationService())
        .environmentObject(HomeService())
}
