import SwiftUI

struct HomeDashboardView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedDestination: DashboardDestination = .home
    @State private var isShowingSettingsMenu = false
    @StateObject private var adminAccess = HomeAdminAccessController()

    var body: some View {
        HStack(spacing: 0) {
            HomeSidebarView(selectedDestination: secureSelectedDestination)
                .frame(width: 74)

            ZStack(alignment: .topTrailing) {
                HomeyTheme.backgroundPrimary
                    .ignoresSafeArea()

                selectedContent
                    .environment(\.homePermissions, homeService.homePermissions(currentUser: authenticationService.currentUser))
                    .environment(\.homePermissionResolution, homeService.permissionResolutionState(currentUser: authenticationService.currentUser))

                SettingsGearButton(
                    selectedDestination: secureSelectedDestination,
                    isShowingSettingsMenu: $isShowingSettingsMenu
                )
                .padding(.top, 28)
                .padding(.trailing, 34)
            }
        }
        .background(HomeyTheme.backgroundPrimary.ignoresSafeArea())
        .task(id: homeService.selectedHomeID) {
            await loadMembersForSelectedHome()
        }
        .task(id: authenticationService.currentUser?.id) {
            await loadInvitationsForAuthenticatedUser()
        }
        .onAppear {
            adminAccess.scope(to: homeService.selectedHomeID)
        }
        .onChange(of: homeService.selectedHomeID) { _, selectedHomeID in
            adminAccess.scope(to: selectedHomeID)
        }
        .onChange(of: selectedDestination) { previousDestination, selectedDestination in
            if previousDestination == .admin, selectedDestination != .admin {
                adminAccess.lock()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                adminAccess.lock()
            }
        }
        .onDisappear {
            adminAccess.lock()
        }
    }

    private var secureSelectedDestination: Binding<DashboardDestination> {
        Binding(
            get: { selectedDestination },
            set: { destination in
                if selectedDestination == .admin, destination != .admin {
                    adminAccess.lock()
                }
                selectedDestination = destination
            }
        )
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedDestination {
        case .home:
            HomePrimaryView()
        case .chores:
            ChoresHomeHubView()
        case .meals:
            MealsHomeHubView()
        case .trips:
            TripsView()
        case .admin:
            AdminAccessView(controller: adminAccess)
        case .homeSettings:
            HomeSettingsView(
                onClose: {
                    selectedDestination = .home
                },
                onShowCalendarCategories: {
                    selectedDestination = .calendarCategories
                }
            )
        case .calendarCategories:
            CalendarCategoriesView {
                selectedDestination = .homeSettings
            }
        case .members:
            HomeMembersView {
                selectedDestination = .home
            }
        case .myAccount:
            MyAccountView(
                onClose: {
                    selectedDestination = .home
                },
                onShowInvitations: {
                    selectedDestination = .homeInvitations
                }
            )
        case .homeInvitations:
            HomeInvitationsView(
                onClose: {
                    selectedDestination = .myAccount
                },
                onSwitchHome: {
                    selectedDestination = .home
                }
            )
        case .changeHome:
            NavigationStack {
                HomeSelectionView(restoresStoredSelectionOnAppear: false) {
                    selectedDestination = .home
                }
            }
        }
    }

    private func loadMembersForSelectedHome() async {
        guard let selectedHome = homeService.selectedHome(),
              let currentUser = authenticationService.currentUser else {
            return
        }

        await homeService.loadMembers(for: selectedHome.id, currentUser: currentUser)
    }

    private func loadInvitationsForAuthenticatedUser() async {
        guard let userID = authenticationService.currentUser?.id else {
            return
        }

        await homeService.loadMyPendingInvitations(for: userID)
    }
}

private struct HomePrimaryView: View {
    var body: some View {
        CalendarHomeHubView()
        .padding(.horizontal, 34)
        .padding(.top, 34)
        .padding(.bottom, 38)
        .frame(maxWidth: 1180, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct DashboardContentView: View {
    @EnvironmentObject private var homeService: HomeService
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var calendarViewModel = DashboardCalendarViewModel()

    var onOpenCalendar: (Date?) -> Void = { _ in }
    var onOpenChores: () -> Void = {}

    private var dashboardMetrics: [DashboardMetric] {
        [
            DashboardMetric(
                title: "Calendar",
                value: "\(calendarViewModel.eventsTodayCount)",
                subtitle: calendarViewModel.eventsTodayCount == 0 ? "No Events Today" : "Events Today",
                systemImage: "calendar",
                accentColor: HomeyTheme.lavender
            ),
            DashboardPlaceholderData.metrics[1],
            DashboardPlaceholderData.metrics[2],
            DashboardPlaceholderData.metrics[3]
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                DashboardHeader()
                    .padding(.trailing, 78)

                HomeHeroCard()

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 4), spacing: 18) {
                    ForEach(dashboardMetrics) { metric in
                        DashboardMetricCard(metric: metric) {
                            if metric.title == "Calendar" {
                                onOpenCalendar(Date())
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 18) {
                    UpcomingEventsCard(
                        events: calendarViewModel.upcomingEvents,
                        categories: calendarViewModel.categories,
                        isLoading: calendarViewModel.isLoading,
                        onOpenCalendar: onOpenCalendar
                    )
                    DashboardChoresCard(onOpenChores: onOpenChores)
                    DashboardGroceriesCard()
                }
            }
            .padding(.leading, 34)
            .padding(.trailing, 34)
            .padding(.top, 34)
            .padding(.bottom, 38)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
        .task(id: homeService.selectedHomeID) {
            calendarViewModel.load(homeId: homeService.selectedHomeID)
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .homeyCalendarEventsDidChange) {
                calendarViewModel.reload()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                calendarViewModel.reload()
            }
        }
        .onDisappear {
            Task {
                await calendarViewModel.clear()
            }
        }
    }
}

private struct DashboardHeader: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @Environment(\.scenePhase) private var scenePhase
    @State private var timeGreeting = TimeOfDayGreeting.greeting()

    private var dashboardGreeting: String {
        guard let currentUser = authenticationService.currentUser else {
            return "\(timeGreeting)!"
        }

        return "\(timeGreeting), \(currentUser.preferredDisplayName)!"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dashboardGreeting)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(HomeyTheme.textPrimary)
                .accessibilityLabel(dashboardGreeting)

            Text("Here’s what’s happening in your home.")
                .font(.title3)
                .foregroundStyle(HomeyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            refreshTimeGreeting()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshTimeGreeting()
            }
        }
    }

    private func refreshTimeGreeting() {
        timeGreeting = TimeOfDayGreeting.greeting()
    }
}

struct HomeSidebarView: View {
    @EnvironmentObject private var homeService: HomeService
    @AppStorage("selectedHomeID") private var storedSelectedHomeID = ""
    @Binding var selectedDestination: DashboardDestination
    var onSelectDestination: () -> Void = {}
    @State private var isShowingHomeMenu = false

    var body: some View {
        ZStack {
            HomeyTheme.sidebarBackground
                .ignoresSafeArea()

            VStack(spacing: 16) {
                VStack(spacing: 14) {
                    ForEach(DashboardDestination.sidebarItems) { item in
                        RailNavigationButton(
                            item: item,
                            isSelected: selectedDestination == item
                        ) {
                            selectedDestination = item
                            onSelectDestination()
                        }
                    }
                }
                .padding(.top, 20)

                Spacer(minLength: 24)

                Button {
                    isShowingHomeMenu.toggle()
                } label: {
                    Image(systemName: "house.and.flag.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(HomeyTheme.primary)
                        .frame(width: 46, height: 46)
                        .background(HomeyTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
                                .stroke(HomeyTheme.borderSubtle, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change Home")
                .popover(isPresented: $isShowingHomeMenu, arrowEdge: .leading) {
                    CompactHomeSwitcher(
                        onSelectHome: selectHome,
                        onShowAllHomes: showAllHomes
                    )
                    .presentationCompactAdaptation(.popover)
                }
                .padding(.bottom, 22)
            }
        }
    }

    private func selectHome(_ home: HomeSummary) {
        storedSelectedHomeID = home.id.uuidString
        homeService.selectHome(id: home.id)
        selectedDestination = .home
        isShowingHomeMenu = false
        onSelectDestination()
    }

    private func showAllHomes() {
        isShowingHomeMenu = false
        selectedDestination = .changeHome
        onSelectDestination()
    }
}

private struct RailNavigationButton: View {
    let item: DashboardDestination
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: item.systemImage)
                .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(isSelected ? HomeyTheme.primary : HomeyTheme.textSecondary)
            .frame(width: 46, height: 46)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
                        .fill(HomeyTheme.primarySoft)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct CompactHomeSwitcher: View {
    @EnvironmentObject private var homeService: HomeService
    let onSelectHome: (HomeSummary) -> Void
    let onShowAllHomes: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Homes")
                .font(.headline.weight(.bold))
                .foregroundStyle(HomeyTheme.textPrimary)
                .padding(.horizontal, 10)

            ForEach(homeService.homes) { home in
                Button {
                    onSelectHome(home)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: home.id == homeService.selectedHomeID ? "checkmark.circle.fill" : "house")
                            .foregroundStyle(HomeyTheme.primary)
                            .frame(width: 24)

                        Text(home.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HomeyTheme.textPrimary)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(10)
                    .background(
                        home.id == homeService.selectedHomeID ? HomeyTheme.primarySoft : Color.clear,
                        in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }

            Divider()

            Button(action: onShowAllHomes) {
                Label("Manage Homes", systemImage: "arrow.left.arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyTheme.primary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 280)
        .background(HomeyTheme.surfacePrimary)
    }
}

private struct SettingsGearButton: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService
    @Binding var selectedDestination: DashboardDestination
    @Binding var isShowingSettingsMenu: Bool
    @State private var isSigningOut = false

    var body: some View {
        Button {
            isShowingSettingsMenu.toggle()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(HomeyTheme.primary)
                .frame(width: 50, height: 50)
                .background(HomeyTheme.surfacePrimary, in: Circle())
                .overlay {
                    Circle()
                        .stroke(HomeyTheme.borderSubtle, lineWidth: 1)
                }
                .shadow(color: HomeyTheme.shadow, radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingSettingsMenu, arrowEdge: .top) {
            SettingsMenuView(
                isSigningOut: isSigningOut,
                onHomeSettings: showHomeSettings,
                onMembers: showMembers,
                onMyAccount: showMyAccount,
                onChangeHome: changeHome,
                onSignOut: signOut
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private func showHomeSettings() {
        isShowingSettingsMenu = false
        selectedDestination = .homeSettings
    }

    private func showMembers() {
        isShowingSettingsMenu = false
        selectedDestination = .members
    }

    private func showMyAccount() {
        isShowingSettingsMenu = false
        selectedDestination = .myAccount
    }

    private func changeHome() {
        isShowingSettingsMenu = false
        selectedDestination = .changeHome
    }

    private func signOut() {
        guard !isSigningOut else {
            return
        }

        isShowingSettingsMenu = false
        isSigningOut = true

        Task {
            // Reuse the central authentication service and let RootView react to the signed-out session state.
            await authenticationService.signOut()
            isSigningOut = false
        }
    }
}

struct HomeHeroCard: View {
    @EnvironmentObject private var homeService: HomeService

    private var selectedHome: HomeSummary? {
        homeService.selectedHome()
    }

    private var members: [HomeMemberDisplay] {
        homeService.membersForSelectedHome()
    }

    private var memberCountText: String {
        guard let selectedHome else {
            return "Choose a Home"
        }

        let count = homeService.memberCountForSelectedHome() ?? selectedHome.memberCount
        return "\(count) \(count == 1 ? "Member" : "Members")"
    }

    var body: some View {
        HStack(spacing: 28) {
            HomeHeroHouseArtwork()

            VStack(alignment: .leading, spacing: 12) {
                Text(selectedHome?.name ?? "No Home Selected")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyTheme.textPrimary)

                Text(memberCountText)
                    .font(.headline)
                    .foregroundStyle(HomeyTheme.textSecondary)

                DashboardMemberAvatarStack(members: members)
                .padding(.top, 2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyTheme.textSecondary.opacity(0.7))
        }
        .padding(26)
        .dashboardCard(cornerRadius: HomeyRadius.page)
    }
}

private struct HomeHeroHouseArtwork: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Image("home_dashboard_house")
            .resizable()
            .scaledToFit()
            .frame(
                width: horizontalSizeClass == .compact ? 170 : 240,
                height: horizontalSizeClass == .compact ? 125 : 170
            )
            .accessibilityLabel("Laroco Family home")
    }
}

struct DashboardMetricCard: View {
    let metric: DashboardMetric
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
                    .fill(metric.accentColor.opacity(0.20))
                    .frame(width: 46, height: 46)

                Image(systemName: metric.systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(metric.accentColor)
            }

            Text(metric.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyTheme.textSecondary)

            Text(metric.value)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(HomeyTheme.textPrimary)

            Text(metric.subtitle)
                .font(.subheadline)
                .foregroundStyle(HomeyTheme.textSecondary)
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .dashboardCard(cornerRadius: HomeyRadius.page)
        }
        .buttonStyle(.plain)
    }
}

struct DashboardSectionCard<Content: View>: View {
    let title: String
    let actionTitle: String
    var action: () -> Void = {}
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(HomeyTheme.textPrimary)

                Spacer()

                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyTheme.primary)
                    .buttonStyle(.plain)
            }

            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 360, maxHeight: 360, alignment: .topLeading)
        .dashboardCard(cornerRadius: HomeyRadius.page)
    }
}

struct UpcomingEventsCard: View {
    var events: [CalendarEvent] = []
    var categories: [CalendarCategory] = []
    var isLoading = false
    var onOpenCalendar: (Date?) -> Void = { _ in }

    var body: some View {
        DashboardSectionCard(title: "Upcoming", actionTitle: "View Calendar", action: {
            onOpenCalendar(nil)
        }) {
            VStack(spacing: 0) {
                if isLoading && events.isEmpty {
                    ProgressView()
                        .tint(HomeyTheme.primary)
                        .frame(maxWidth: .infinity, minHeight: 190)
                        .accessibilityLabel("Loading upcoming events")
                } else if events.isEmpty {
                    UpcomingEventsEmptyState()
                } else {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        Button {
                            onOpenCalendar(event.occurrenceStartsAt)
                        } label: {
                            UpcomingEventRow(event: event, categories: categories)
                        }
                        .buttonStyle(.plain)

                        if index < events.count - 1 {
                            Divider()
                                .overlay(HomeyTheme.borderSubtle)
                        }
                    }
                }

                Spacer(minLength: 16)

                SoftDashboardButton(systemImage: "calendar", title: "View Full Calendar") {
                    onOpenCalendar(nil)
                }
            }
        }
    }
}

private struct UpcomingEventRow: View {
    let event: CalendarEvent
    let categories: [CalendarCategory]

    var body: some View {
        HStack(spacing: 13) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)

            Image(systemName: event.categoryIconName ?? "calendar")
                .font(.body.weight(.medium))
                .foregroundStyle(HomeyTheme.primary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyTheme.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(HomeyTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyTheme.textSecondary.opacity(0.7))
        }
        .padding(.vertical, 15)
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        CalendarEventColorResolver.color(for: event, categories: categories, fallback: HomeyTheme.lavender)
    }

    private var subtitle: String {
        let dateText = DashboardCalendarFormatters.eventDate.string(from: event.occurrenceStartsAt)
        let timeText = event.isAllDay ? "All Day" : "\(DashboardCalendarFormatters.eventTime.string(from: event.occurrenceStartsAt))"
        let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if location.isEmpty {
            return "\(dateText) • \(timeText)"
        }

        return "\(dateText) • \(timeText) • \(location)"
    }
}

private struct UpcomingEventsEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
                    .fill(HomeyTheme.primarySoft)
                    .frame(width: 54, height: 54)

                Image(systemName: "calendar")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(HomeyTheme.primary)
            }
            .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("No Upcoming Events")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyTheme.textPrimary)

                Text("Nothing is scheduled yet.")
                    .font(.subheadline)
                    .foregroundStyle(HomeyTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .accessibilityElement(children: .combine)
    }
}

struct DashboardChoresCard: View {
    @EnvironmentObject private var attentionStore: ChoresAttentionStore
    var onOpenChores: () -> Void = {}

    var body: some View {
        DashboardSectionCard(title: "Chores", actionTitle: "View All", action: onOpenChores) {
            VStack(spacing: 0) {
                if attentionStore.dashboardAttentionCount > 0 {
                    HStack(spacing: 10) {
                        AttentionBadge(count: attentionStore.dashboardAttentionCount)

                        Text("\(attentionStore.dashboardAttentionCount.formatted(.number)) \(attentionStore.dashboardAttentionCount == 1 ? "chore is" : "chores are") not started this week")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(HomeyTheme.textSecondary)

                        Spacer()
                    }
                    .padding(.bottom, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Chores, \(attentionStore.dashboardAttentionCount) not started this week")
                }

                ForEach(DashboardPlaceholderData.chores) { chore in
                    ChoreDashboardRow(chore: chore)

                    if chore.id != DashboardPlaceholderData.chores.last?.id {
                        Divider()
                            .overlay(HomeyTheme.borderSubtle)
                    }
                }

                Spacer(minLength: 16)

                SoftDashboardButton(systemImage: "checklist", title: "Go to Chores", action: onOpenChores)
            }
        }
    }
}

private struct ChoreDashboardRow: View {
    let chore: DashboardChore

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .stroke(HomeyTheme.textSecondary.opacity(0.42), lineWidth: 1.7)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(chore.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyTheme.textPrimary)
                    .lineLimit(1)

                Text(chore.dueText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(HomeyTheme.danger)
            }

            Spacer()

            AvatarPlaceholderView(initials: chore.initials, color: chore.color, size: 34)
        }
        .padding(.vertical, 13)
    }
}

struct DashboardGroceriesCard: View {
    var body: some View {
        DashboardSectionCard(title: "Groceries", actionTitle: "View List") {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(DashboardPlaceholderData.groceries) { item in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(HomeyTheme.peach.opacity(0.18))
                                    .frame(width: 24, height: 24)
                                    .overlay {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 6))
                                            .foregroundStyle(HomeyTheme.peach)
                                    }

                                Text(item.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(HomeyTheme.textPrimary)
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    GroceryBagPlaceholder()
                        .frame(width: 84, height: 108)
                }

                Spacer(minLength: 16)

                SoftDashboardButton(systemImage: "cart.fill", title: "Go to Grocery List")
            }
        }
    }
}

private struct GroceryBagPlaceholder: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: HomeyRadius.card, style: .continuous)
                .fill(HomeyTheme.borderSubtle.opacity(0.75))

            Image(systemName: "basket.fill")
                .font(.system(size: 42))
                .foregroundStyle(HomeyTheme.peach)
        }
    }
}

private struct SoftDashboardButton: View {
    let systemImage: String
    let title: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(HomeyTheme.primary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(HomeyTheme.primarySoft, in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SettingsMenuView: View {
    var isSigningOut = false
    var onHomeSettings: () -> Void = {}
    var onMembers: () -> Void = {}
    var onMyAccount: () -> Void = {}
    var onChangeHome: () -> Void = {}
    var onSignOut: () -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            SettingsMenuRow(
                title: "Home Settings",
                subtitle: "Edit home name, timezone, and more",
                systemImage: "gearshape",
                action: onHomeSettings
            )
            SettingsMenuRow(
                title: "Members",
                subtitle: "View and manage members",
                systemImage: "person.2",
                action: onMembers
            )
            SettingsMenuRow(
                title: "My Account",
                subtitle: "Profile and personal preferences",
                systemImage: "person.crop.circle",
                action: onMyAccount
            )

            Divider()
                .padding(.vertical, 4)

            SettingsMenuRow(
                title: "Change Home",
                subtitle: "Switch to a different home",
                systemImage: "arrow.left.arrow.right",
                action: onChangeHome
            )

            Divider()
                .padding(.vertical, 4)

            SettingsMenuRow(
                title: "Sign Out",
                subtitle: "Sign out of Homey",
                systemImage: "rectangle.portrait.and.arrow.right",
                role: .destructive,
                isLoading: isSigningOut,
                action: onSignOut
            )
        }
        .padding(12)
        .frame(width: 360)
        .background(HomeyTheme.surfacePrimary)
    }
}

private struct SettingsMenuRow: View {
    enum Role {
        case normal
        case destructive
    }

    let title: String
    let subtitle: String
    let systemImage: String
    var role: Role = .normal
    var isLoading = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: HomeyRadius.control, style: .continuous)
                        .fill(iconColor.opacity(0.14))
                        .frame(width: 42, height: 42)

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(iconColor)
                    } else {
                        Image(systemName: systemImage)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(iconColor)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(titleColor)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(HomeyTheme.textSecondary)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(10)
            .contentShape(RoundedRectangle(cornerRadius: HomeyRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var iconColor: Color {
        role == .destructive ? HomeyTheme.danger : HomeyTheme.primary
    }

    private var titleColor: Color {
        role == .destructive ? HomeyTheme.danger : HomeyTheme.textPrimary
    }
}

struct AvatarPlaceholderView: View {
    let initials: String
    let color: Color
    var size: CGFloat = 38

    var body: some View {
        Text(initials)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
            .overlay {
                Circle()
                    .stroke(HomeyTheme.surfacePrimary, lineWidth: 3)
            }
    }
}

struct PlaceholderModuleView: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            HomeyTheme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyTheme.textPrimary)

                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(HomeyTheme.textSecondary)
            }
            .padding(40)
            .frame(maxWidth: 420)
            .dashboardCard(cornerRadius: HomeyRadius.page)
        }
    }
}

extension View {
    func dashboardCard(cornerRadius: CGFloat) -> some View {
        let cornerRadius = min(cornerRadius, HomeyRadius.page)
        return background(HomeyTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(HomeyTheme.borderSubtle, lineWidth: 1)
            }
            .shadow(color: HomeyTheme.shadow, radius: 8, x: 0, y: 3)
    }
}

enum DashboardDestination: String, CaseIterable, Identifiable {
    case home
    case chores
    case meals
    case trips
    case admin
    case homeSettings
    case calendarCategories
    case members
    case myAccount
    case homeInvitations
    case changeHome

    var id: String { rawValue }

    static let sidebarItems: [DashboardDestination] = [
        .home,
        .chores,
        .meals,
        .trips,
        .admin
    ]

    var title: String {
        switch self {
        case .home:
            "Home"
        case .chores:
            "Chores"
        case .meals:
            "Meals"
        case .trips:
            "Trips"
        case .admin:
            "Admin"
        case .homeSettings:
            "Home Settings"
        case .calendarCategories:
            "Calendar Categories"
        case .members:
            "Members"
        case .myAccount:
            "My Account"
        case .homeInvitations:
            "Home Invitations"
        case .changeHome:
            "Change Home"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            "house.fill"
        case .chores:
            "checklist"
        case .meals:
            "fork.knife"
        case .trips:
            "airplane"
        case .admin:
            "gearshape.fill"
        case .homeSettings:
            "gearshape"
        case .calendarCategories:
            "tag.fill"
        case .members:
            "person.2"
        case .myAccount:
            "person.crop.circle"
        case .homeInvitations:
            "envelope.badge"
        case .changeHome:
            "arrow.left.arrow.right"
        }
    }
}

struct DashboardMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let accentColor: Color
}

private enum DashboardCalendarFormatters {
    static let eventDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let eventTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

struct DashboardEvent: Identifiable {
    let id = UUID()
    let title: String
    let time: String
    let systemImage: String
    let statusColor: Color
}

struct DashboardChore: Identifiable {
    let id = UUID()
    let title: String
    let dueText: String
    let initials: String
    let color: Color
}

struct DashboardGroceryItem: Identifiable {
    let id = UUID()
    let name: String
}

struct DashboardMember: Identifiable {
    let id = UUID()
    let initials: String
    let color: Color
}

enum DashboardPlaceholderData {
    static let members = [
        DashboardMember(initials: "JL", color: HomeyTheme.primary),
        DashboardMember(initials: "ML", color: HomeyTheme.success),
        DashboardMember(initials: "AL", color: HomeyTheme.peach),
        DashboardMember(initials: "EL", color: HomeyTheme.lavender)
    ]

    static let metrics = [
        DashboardMetric(title: "Calendar", value: "2", subtitle: "Events Today", systemImage: "calendar", accentColor: HomeyTheme.lavender),
        DashboardMetric(title: "Chores", value: "3", subtitle: "To Do", systemImage: "checklist", accentColor: HomeyTheme.success),
        DashboardMetric(title: "Groceries", value: "12", subtitle: "Items", systemImage: "cart.fill", accentColor: HomeyTheme.coral),
        DashboardMetric(title: "Meals", value: "1", subtitle: "Planned", systemImage: "fork.knife", accentColor: HomeyTheme.peach)
    ]

    static let events = [
        DashboardEvent(title: "Dinner with Grandma", time: "Today at 6:00 PM", systemImage: "fork.knife", statusColor: HomeyTheme.lavender),
        DashboardEvent(title: "Soccer Practice", time: "Today at 5:30 PM", systemImage: "soccerball", statusColor: HomeyTheme.success)
    ]

    static let chores = [
        DashboardChore(title: "Take out the trash", dueText: "Due today", initials: "JL", color: HomeyTheme.primary),
        DashboardChore(title: "Wipe down countertops", dueText: "Due today", initials: "ML", color: HomeyTheme.success),
        DashboardChore(title: "Feed the dog", dueText: "Due today", initials: "AL", color: HomeyTheme.peach)
    ]

    static let groceries = [
        DashboardGroceryItem(name: "Milk"),
        DashboardGroceryItem(name: "Eggs"),
        DashboardGroceryItem(name: "Chicken"),
        DashboardGroceryItem(name: "Bananas"),
        DashboardGroceryItem(name: "Apples")
    ]
}


#Preview("Home Dashboard - iPad Landscape", traits: .landscapeLeft) {
    HomeDashboardView()
        .environmentObject(AuthenticationService())
        .environmentObject(HomeService())
}

#Preview("Sidebar") {
    HomeSidebarPreview()
}

private struct HomeSidebarPreview: View {
    @State private var selectedDestination: DashboardDestination = .home

    var body: some View {
        HomeSidebarView(selectedDestination: $selectedDestination)
            .frame(width: 280, height: 820)
    }
}

#Preview("Home Hero Card") {
    HomeHeroCard()
        .padding()
        .background(HomeyTheme.backgroundPrimary)
}

#Preview("Metric Card") {
    DashboardMetricCard(metric: DashboardPlaceholderData.metrics[0])
        .frame(width: 220)
        .padding()
        .background(HomeyTheme.backgroundPrimary)
}

#Preview("Settings Menu") {
    SettingsMenuView()
        .environmentObject(AuthenticationService())
}

#Preview("Upcoming Card") {
    UpcomingEventsCard()
        .frame(width: 360)
        .padding()
        .background(HomeyTheme.backgroundPrimary)
}

#Preview("Chores Card") {
    DashboardChoresCard()
        .environmentObject(ChoresAttentionStore())
        .frame(width: 360)
        .padding()
        .background(HomeyTheme.backgroundPrimary)
}

#Preview("Groceries Card") {
    DashboardGroceriesCard()
        .frame(width: 360)
        .padding()
        .background(HomeyTheme.backgroundPrimary)
}
