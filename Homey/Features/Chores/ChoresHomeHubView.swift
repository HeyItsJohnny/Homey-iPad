import Combine
import SwiftUI

private struct MemberChoreRow: Identifiable, Hashable {
    let occurrence: ChoreOccurrence
    let assignee: ChoreOccurrenceAssignee?
    let userID: UUID
    let roomName: String

    var id: String { "\(occurrence.id.uuidString):\(userID.uuidString)" }
    var status: ChoreOccurrenceStatus { assignee?.status.personalOccurrenceStatus ?? occurrence.status }
    var isCompleted: Bool { status == .completed }
}

@MainActor
private final class ChoresHomeHubViewModel: ObservableObject {
    @Published private(set) var tasksByMember: [UUID: [MemberDailyTask]] = [:]
    @Published private(set) var choresByMember: [UUID: [MemberChoreRow]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var processingTaskIDs: Set<String> = []
    @Published private(set) var processingChoreIDs: Set<String> = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var actionErrorMessage: String?
    @Published private(set) var localDate = Date()
    @Published private(set) var selectedDate = Date()

    private let dailyTaskService = DailyTaskService()
    private let choresRepository = ChoresRepository()
    private var activeHomeID: UUID?
    private var currentUserID: UUID?
    private var activeRole: HomeMemberRole?
    private var timezone = TimeZone.autoupdatingCurrent
    private var requestedDate = ""
    private var activeLoadID = UUID()

    var allTasks: [MemberDailyTask] { tasksByMember.values.flatMap { $0 } }
    var allChores: [MemberChoreRow] { choresByMember.values.flatMap { $0 } }
    var completedCount: Int { allTasks.filter(\.isCompleted).count + allChores.filter(\.isCompleted).count }
    var remainingCount: Int { allTasks.filter { !$0.isCompleted }.count + allChores.filter { !$0.isCompleted }.count }

    func configure(
        homeID: UUID?,
        currentUserID: UUID?,
        role: HomeMemberRole?,
        timezoneIdentifier: String,
        force: Bool = false
    ) async {
        guard let homeID, let currentUserID else {
            reset()
            return
        }

        let nextTimezone = TimeZone(identifier: timezoneIdentifier) ?? .autoupdatingCurrent
        let homeChanged = activeHomeID != homeID
        if homeChanged {
            selectedDate = Date()
        }
        let nextDate = DailyTaskLocalDate.string(for: selectedDate, timezone: nextTimezone)
        let contextChanged = homeChanged
            || self.currentUserID != currentUserID
            || activeRole != role
            || requestedDate != nextDate

        if contextChanged {
            activeLoadID = UUID()
            tasksByMember = [:]
            choresByMember = [:]
            processingTaskIDs = []
            processingChoreIDs = []
            errorMessage = nil
            actionErrorMessage = nil
        }

        activeHomeID = homeID
        self.currentUserID = currentUserID
        activeRole = role
        timezone = nextTimezone
        requestedDate = nextDate
        localDate = Date()

        if contextChanged || force || (tasksByMember.isEmpty && choresByMember.isEmpty) {
            await load()
        }
    }

    func refresh() async {
        errorMessage = nil
        actionErrorMessage = nil
        guard activeHomeID != nil else { return }
        let nextDate = DailyTaskLocalDate.string(for: selectedDate, timezone: timezone)
        if requestedDate != nextDate {
            requestedDate = nextDate
            tasksByMember = [:]
            choresByMember = [:]
        }
        localDate = Date()
        await load()
    }

    func moveSelectedDate(by dayOffset: Int) async {
        guard activeHomeID != nil else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        guard let nextDate = calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: calendar.startOfDay(for: selectedDate)
        ) else { return }

        selectedDate = nextDate
        requestedDate = DailyTaskLocalDate.string(for: nextDate, timezone: timezone)
        tasksByMember = [:]
        choresByMember = [:]
        actionErrorMessage = nil
        await load()
    }

    func returnToToday() async {
        guard !isViewingToday else { return }
        selectedDate = Date()
        requestedDate = DailyTaskLocalDate.string(for: selectedDate, timezone: timezone)
        tasksByMember = [:]
        choresByMember = [:]
        actionErrorMessage = nil
        await load()
    }

    var isViewingToday: Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        return calendar.isDate(selectedDate, inSameDayAs: Date())
    }

    func waitForMidnightAndRefresh(timezoneIdentifier: String) async {
        let refreshTimezone = TimeZone(identifier: timezoneIdentifier) ?? .autoupdatingCurrent
        while !Task.isCancelled {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = refreshTimezone
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) else { return }
            let wasViewingToday = calendar.isDate(selectedDate, inSameDayAs: Date())
            let interval = max(1, tomorrow.timeIntervalSinceNow + 1)
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return
            }
            localDate = Date()
            if wasViewingToday {
                selectedDate = localDate
                requestedDate = DailyTaskLocalDate.string(for: selectedDate, timezone: refreshTimezone)
                tasksByMember = [:]
                choresByMember = [:]
                await load()
            }
        }
    }

    func canToggle(_ task: MemberDailyTask) -> Bool {
        let hasPermission = activeRole == .owner || activeRole == .admin || task.userID == currentUserID
        guard hasPermission else { return false }

        switch selectedDateRelation {
        case .today:
            return true
        case .past:
            return !task.isCompleted
        case .future:
            return false
        }
    }

    func isProcessing(_ task: MemberDailyTask) -> Bool {
        processingTaskIDs.contains(task.id)
    }

    func canInteract(with chore: MemberChoreRow) -> Bool {
        let hasPermission = activeRole == .owner || activeRole == .admin || chore.userID == currentUserID
        guard hasPermission else { return false }

        switch chore.status {
        case .notStarted, .inProgress, .needsRedo, .awaitingApproval:
            return true
        case .completed, .skipped, .cancelled:
            return false
        }
    }

    func isProcessing(_ chore: MemberChoreRow) -> Bool {
        processingChoreIDs.contains(chore.id)
    }

    func toggle(_ task: MemberDailyTask) async {
        guard let homeID = activeHomeID, canToggle(task), !processingTaskIDs.contains(task.id) else { return }
        processingTaskIDs.insert(task.id)
        actionErrorMessage = nil
        defer { processingTaskIDs.remove(task.id) }

        do {
            if task.isCompleted {
                var completionID = task.completionID
                if completionID == nil {
                    try await reloadTasks(homeID: homeID)
                    completionID = tasksByMember[task.userID]?
                        .first(where: { $0.taskID == task.taskID })?
                        .completionID
                }
                guard let completionID else {
                    #if DEBUG
                    print("[Homey] TASK UNCHECK ERROR")
                    print("code: missing_completion_id")
                    print("message: Checked Daily Task did not include its daily_task_completions.id")
                    print("detail: task_id=\(task.taskID.uuidString) user_id=\(task.userID.uuidString) selected_date=\(requestedDate)")
                    print("hint: Verify get_daily_tasks returns completion_id for completed assignments")
                    #endif
                    throw DailyTaskError.updateFailed
                }
                try await dailyTaskService.undo(
                    homeID: homeID,
                    taskID: task.taskID,
                    completionID: completionID,
                    selectedDate: requestedDate
                )
            } else {
                try await dailyTaskService.complete(
                    homeID: homeID,
                    taskID: task.taskID,
                    userID: task.userID,
                    date: requestedDate
                )
            }
            try await reloadTasks(homeID: homeID)
            NotificationCenter.default.post(name: Notification.Name("homeyDailyTasksDidChange"), object: nil)
        } catch is CancellationError {
            return
        } catch {
            actionErrorMessage = error.localizedDescription
            try? await reloadTasks(homeID: homeID)
        }
    }

    func toggle(_ chore: MemberChoreRow) async {
        guard let homeID = activeHomeID,
              canInteract(with: chore),
              !processingChoreIDs.contains(chore.id) else { return }

        if chore.status == .awaitingApproval {
            #if DEBUG
            let pendingSubmission = try? await choresRepository.fetchPendingSubmission(
                occurrenceId: chore.occurrence.id
            )
            print("[Homey] CHORE UNCHECK REQUEST")
            print("home_id: \(homeID.uuidString)")
            print("occurrence_id: \(chore.occurrence.id.uuidString)")
            print("status: \(chore.status.rawValue)")
            print("submission_id: \(pendingSubmission?.id.uuidString ?? "nil")")
            print("[Homey] CHORE UNCHECK ERROR")
            print("code: missing_unsubmit_rpc")
            print("message: No safe Chore unsubmit/reopen RPC is available")
            print("detail: awaiting_approval cannot be reversed from the Home Hub without an atomic backend operation")
            print("hint: Add an authenticated Chore-specific undo/unsubmit RPC")
            #endif
            actionErrorMessage = "Pending chores can’t be unchecked from the Home Hub yet."
            return
        }

        processingChoreIDs.insert(chore.id)
        actionErrorMessage = nil
        defer { processingChoreIDs.remove(chore.id) }

        do {
            _ = try await choresRepository.submitChoreFromHomeBoard(
                occurrenceId: chore.occurrence.id,
                assigneeUserId: chore.userID,
                note: nil,
                photoPath: nil
            )
            try await reloadChores(homeID: homeID)
            NotificationCenter.default.post(name: .homeyChoresDidChange, object: nil)
        } catch is CancellationError {
            return
        } catch {
            actionErrorMessage = error.localizedDescription
            try? await reloadChores(homeID: homeID)
        }
    }

    private func load() async {
        guard let homeID = activeHomeID else { return }
        let loadID = UUID()
        activeLoadID = loadID
        isLoading = true
        errorMessage = nil
        defer {
            if activeLoadID == loadID { isLoading = false }
        }

        let range = localDayRange(for: selectedDate)
        do {
            async let loadedTasks = dailyTaskService.fetchTasks(homeID: homeID, date: requestedDate)
            async let loadedOccurrences = choresRepository.fetchOccurrences(homeId: homeID, from: range.start, through: range.end)
            async let loadedRooms = choresRepository.fetchRooms(homeId: homeID)
            let (taskRows, occurrences, rooms) = try await (loadedTasks, loadedOccurrences, loadedRooms)
            let assignees = try await choresRepository.fetchOccurrenceAssignees(occurrenceIds: occurrences.map(\.id))
            try Task.checkCancellation()
            guard activeLoadID == loadID, activeHomeID == homeID else { return }

            tasksByMember = Dictionary(grouping: taskRows.map(MemberDailyTask.init(row:)), by: \.userID)
                .mapValues(sortTasks)
            choresByMember = groupChores(occurrences: occurrences, assignees: assignees, rooms: rooms)
        } catch is CancellationError {
            return
        } catch {
            guard activeLoadID == loadID else { return }
            errorMessage = "We couldn't load tasks and chores for this date."
        }
    }

    private func reloadTasks(homeID: UUID) async throws {
        let rows = try await dailyTaskService.fetchTasks(homeID: homeID, date: requestedDate)
        guard activeHomeID == homeID else { return }
        tasksByMember = Dictionary(grouping: rows.map(MemberDailyTask.init(row:)), by: \.userID)
            .mapValues(sortTasks)
    }

    private func reloadChores(homeID: UUID) async throws {
        let range = localDayRange(for: selectedDate)
        async let loadedOccurrences = choresRepository.fetchOccurrences(
            homeId: homeID,
            from: range.start,
            through: range.end
        )
        async let loadedRooms = choresRepository.fetchRooms(homeId: homeID)
        let (occurrences, rooms) = try await (loadedOccurrences, loadedRooms)
        let assignees = try await choresRepository.fetchOccurrenceAssignees(occurrenceIds: occurrences.map(\.id))
        guard activeHomeID == homeID else { return }
        choresByMember = groupChores(occurrences: occurrences, assignees: assignees, rooms: rooms)
    }

    private func groupChores(
        occurrences: [ChoreOccurrence],
        assignees: [ChoreOccurrenceAssignee],
        rooms: [ChoreRoom]
    ) -> [UUID: [MemberChoreRow]] {
        let occurrencesByID = Dictionary(uniqueKeysWithValues: occurrences.map { ($0.id, $0) })
        let roomsByID = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0.name) })
        var rows: [MemberChoreRow] = assignees.compactMap { assignee in
            guard let occurrence = occurrencesByID[assignee.occurrenceId] else { return nil }
            let roomName = occurrence.roomIdSnapshot.flatMap { roomsByID[$0] } ?? "No Room"
            return MemberChoreRow(occurrence: occurrence, assignee: assignee, userID: assignee.userId, roomName: roomName)
        }

        let representedOccurrenceIDs = Set(rows.map { $0.occurrence.id })
        rows.append(contentsOf: occurrences.compactMap { occurrence in
            guard !representedOccurrenceIDs.contains(occurrence.id), let claimedBy = occurrence.claimedBy else { return nil }
            let roomName = occurrence.roomIdSnapshot.flatMap { roomsByID[$0] } ?? "No Room"
            return MemberChoreRow(occurrence: occurrence, assignee: nil, userID: claimedBy, roomName: roomName)
        })

        return Dictionary(grouping: rows, by: \.userID).mapValues {
            $0.sorted {
                if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
                if $0.occurrence.dueAt != $1.occurrence.dueAt { return $0.occurrence.dueAt < $1.occurrence.dueAt }
                return $0.occurrence.titleSnapshot.localizedCaseInsensitiveCompare($1.occurrence.titleSnapshot) == .orderedAscending
            }
        }
    }

    private func sortTasks(_ tasks: [MemberDailyTask]) -> [MemberDailyTask] {
        tasks.sorted {
            if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func localDayRange(for date: Date) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let start = calendar.startOfDay(for: date)
        return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400))
    }

    private var selectedDateRelation: SelectedDateRelation {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let selectedDay = calendar.startOfDay(for: selectedDate)
        let today = calendar.startOfDay(for: Date())

        if selectedDay < today { return .past }
        if selectedDay > today { return .future }
        return .today
    }

    private func reset() {
        activeLoadID = UUID()
        activeHomeID = nil
        currentUserID = nil
        activeRole = nil
        timezone = .autoupdatingCurrent
        requestedDate = ""
        selectedDate = Date()
        tasksByMember = [:]
        choresByMember = [:]
        processingTaskIDs = []
        processingChoreIDs = []
        isLoading = false
        errorMessage = nil
        actionErrorMessage = nil
    }
}

private enum SelectedDateRelation {
    case past
    case today
    case future
}

struct ChoresHomeHubView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = ChoresHomeHubViewModel()
    @State private var orderedMembers: [HomeMemberDisplay] = []
    @State private var isPersistingMemberOrder = false
    @State private var reorderErrorMessage: String?
    @State private var refreshErrorMessage: String?

    private var homeID: UUID? { homeService.selectedHomeID }
    private var timezoneIdentifier: String { homeService.selectedHome()?.timezone ?? TimeZone.autoupdatingCurrent.identifier }
    private var timezone: TimeZone { TimeZone(identifier: timezoneIdentifier) ?? .autoupdatingCurrent }
    private var currentUserID: UUID? { authenticationService.currentUser?.id }
    private var currentRole: HomeMemberRole? { homeService.selectedHomeRole(currentUserID: currentUserID) }
    private var members: [HomeMemberDisplay] { orderedMembers }
    private var canReorderMembers: Bool { currentRole == .owner || currentRole == .admin }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            GeometryReader { proxy in
                ScrollView(.vertical) {
                    householdSurface
                        .frame(height: proxy.size.height)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await refreshChoresHomeHub()
                }
            }
        }
        .padding(.horizontal, 34)
        .padding(.top, 34)
        .padding(.bottom, 38)
        .frame(maxWidth: 1180, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .center)
        .task(id: loadKey) {
            await viewModel.configure(
                homeID: homeID,
                currentUserID: currentUserID,
                role: currentRole,
                timezoneIdentifier: timezoneIdentifier
            )
        }
        .task(id: "\(homeID?.uuidString ?? "no-home"):\(timezoneIdentifier)") {
            await viewModel.waitForMidnightAndRefresh(timezoneIdentifier: timezoneIdentifier)
        }
        .task(id: "responsibility-refresh:\(homeID?.uuidString ?? "no-home")") {
            for await _ in NotificationCenter.default.notifications(named: .homeyChoresDidChange) {
                guard !Task.isCancelled else { return }
                await viewModel.refresh()
            }
        }
        .onAppear(perform: synchronizeMemberOrder)
        .onChange(of: homeID) { _, _ in
            orderedMembers = []
            reorderErrorMessage = nil
            refreshErrorMessage = nil
            synchronizeMemberOrder()
        }
        .onChange(of: homeService.members) { _, _ in
            guard !isPersistingMemberOrder else { return }
            synchronizeMemberOrder()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.refresh() } }
        }
    }

    private var loadKey: String {
        [
            homeID?.uuidString ?? "no-home",
            currentUserID?.uuidString ?? "no-user",
            currentRole?.rawValue ?? "no-role",
            timezoneIdentifier,
            members.map { $0.userId.uuidString }.sorted().joined(separator: ",")
        ].joined(separator: ":")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Chores")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Today's tasks and chores by family member.")
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
                Text(selectedDateLabel)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(HomeyTheme.primary)
            .padding(.horizontal, 13)
            .frame(minHeight: 38)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(selectedDateLabel)

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

    private var selectedDateLabel: String {
        DailyTaskLocalDate.displayString(for: viewModel.selectedDate, timezone: timezone)
    }

    private var householdSurface: some View {
        VStack(alignment: .leading, spacing: 18) {
            summaryBar

            if let message = refreshErrorMessage ?? reorderErrorMessage ?? viewModel.actionErrorMessage ?? viewModel.errorMessage {
                HStack(spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(message)
                    Spacer()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyTheme.danger)
                .padding(12)
                .background(HomeyTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
            }

            if viewModel.isLoading && members.isEmpty {
                ProgressView("Loading household work…")
                    .tint(HomeyTheme.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if members.isEmpty {
                emptyHousehold
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                            reorderableMemberColumn(member, index: index)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.visible)
                .scrollTargetBehavior(.viewAligned)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardCard(cornerRadius: HomeyRadius.page)
    }

    private var summaryBar: some View {
        HStack(spacing: 10) {
            summaryMetric("Tasks", value: viewModel.allTasks.count, icon: "checklist", color: HomeyTheme.lavender)
            summaryMetric("Chores", value: viewModel.allChores.count, icon: "house.fill", color: HomeyTheme.peach)
            summaryMetric("Completed", value: viewModel.completedCount, icon: "checkmark.circle.fill", color: HomeyTheme.success)
            summaryMetric("Remaining", value: viewModel.remainingCount, icon: "circle.dotted", color: HomeyTheme.primary)
        }
    }

    private func summaryMetric(_ title: String, value: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text("\(value)")
                .font(.headline.weight(.bold))
                .foregroundStyle(HomeyTheme.textPrimary)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyTheme.textSecondary)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
    }

    @ViewBuilder
    private func reorderableMemberColumn(_ member: HomeMemberDisplay, index: Int) -> some View {
        let column = memberColumn(member, color: memberColor(index))
            .frame(width: 252)

        if canReorderMembers {
            column.dropDestination(for: String.self) { items, _ in
                guard let value = items.first,
                      let draggedMembershipID = UUID(uuidString: value) else { return false }
                reorderMember(draggedMembershipID, relativeTo: member.membershipId)
                return true
            }
        } else {
            column
        }
    }

    private func memberColumn(_ member: HomeMemberDisplay, color: Color) -> some View {
        let tasks = viewModel.tasksByMember[member.userId] ?? []
        let chores = viewModel.choresByMember[member.userId] ?? []
        let taskCompleted = tasks.filter(\.isCompleted).count
        let choreCompleted = chores.filter(\.isCompleted).count
        let allDone = !tasks.isEmpty || !chores.isEmpty
            ? taskCompleted == tasks.count && choreCompleted == chores.count
            : false

        return VStack(spacing: 0) {
            memberHeader(
                member,
                color: color,
                taskCompleted: taskCompleted,
                taskCount: tasks.count,
                choreCompleted: choreCompleted,
                choreCount: chores.count
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    itemSectionHeader("Tasks", count: "\(taskCompleted)/\(tasks.count)")
                    if tasks.isEmpty {
                        emptySection("No daily tasks", icon: "checklist")
                    } else {
                        VStack(spacing: 8) {
                            ForEach(tasks) { task in taskRow(task) }
                        }
                    }

                    Divider().overlay(HomeyTheme.borderSubtle)

                    itemSectionHeader("Chores", count: "\(choreCompleted)/\(chores.count)")
                    if chores.isEmpty {
                        emptySection("No chores today", icon: "house")
                    } else {
                        VStack(spacing: 8) {
                            ForEach(chores) { chore in choreRow(chore) }
                        }
                    }

                    if allDone {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Great job, \(member.displayName)!", systemImage: "sparkles")
                                .font(.subheadline.weight(.bold))
                            Text("All done for today.")
                                .font(.caption)
                        }
                        .foregroundStyle(HomeyTheme.success)
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(HomeyTheme.success.opacity(0.10), in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
                    }
                }
                .padding(14)
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

    @ViewBuilder
    private func memberHeader(
        _ member: HomeMemberDisplay,
        color: Color,
        taskCompleted: Int,
        taskCount: Int,
        choreCompleted: Int,
        choreCount: Int
    ) -> some View {
        let content = VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 11) {
                AvatarView(
                    imageURL: member.avatarURL,
                    initials: member.initials,
                    size: 48,
                    accentColor: color,
                    borderColor: .white.opacity(0.72),
                    borderWidth: 2,
                    showsShadow: false,
                    accessibilityLabel: member.displayName
                )
                Text(member.displayName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(HomeyTheme.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 4)
                if canReorderMembers {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyTheme.primary.opacity(0.62))
                        .accessibilityHidden(true)
                }
            }

            Text("\(taskCompleted) of \(taskCount) tasks • \(choreCompleted) of \(choreCount) chores")
                .font(.caption.weight(.semibold))
                .foregroundStyle(HomeyTheme.textSecondary)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.18))
        .contentShape(Rectangle())

        if canReorderMembers {
            content
                .draggable(member.membershipId.uuidString) {
                    Label(member.displayName, systemImage: "line.3.horizontal")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(HomeyTheme.textPrimary)
                        .padding(14)
                        .background(HomeyTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
                }
                .accessibilityHint("Long press and drag to reorder this member column")
                .accessibilityAction(named: Text("Move Left")) {
                    moveMember(member.membershipId, by: -1)
                }
                .accessibilityAction(named: Text("Move Right")) {
                    moveMember(member.membershipId, by: 1)
                }
        } else {
            content
        }
    }

    private func itemSectionHeader(_ title: String, count: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyTheme.textPrimary)
            Spacer()
            Text(count)
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyTheme.textSecondary)
        }
    }

    private func taskRow(_ task: MemberDailyTask) -> some View {
        Button {
            Task { await viewModel.toggle(task) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Group {
                    if viewModel.isProcessing(task) {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.isCompleted ? HomeyTheme.success : HomeyTheme.textSecondary)
                    }
                }
                .frame(width: 20, height: 20)

                Text(task.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(task.isCompleted ? HomeyTheme.textSecondary : HomeyTheme.textPrimary)
                    .strikethrough(task.isCompleted, color: HomeyTheme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if task.points > 0 { pointsPill(task.points) }
            }
            .padding(11)
            .background(task.isCompleted ? HomeyTheme.success.opacity(0.08) : .white.opacity(0.42), in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canToggle(task) || viewModel.isProcessing(task))
        .accessibilityLabel("\(task.name), \(task.isCompleted ? "completed" : "not completed")")
    }

    private func choreRow(_ chore: MemberChoreRow) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Button {
                Task { await viewModel.toggle(chore) }
            } label: {
                Group {
                    if viewModel.isProcessing(chore) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(choreBubbleColor(chore.status))
                    } else {
                        Image(systemName: choreBubbleIsChecked(chore.status) ? "checkmark.circle.fill" : "circle")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(choreBubbleColor(chore.status))
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canInteract(with: chore) || viewModel.isProcessing(chore))
            .accessibilityLabel(choreBubbleAccessibilityLabel(chore))

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 7) {
                    Text(chore.occurrence.titleSnapshot)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeyTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if chore.occurrence.pointsValueSnapshot > 0 {
                        pointsPill(chore.occurrence.pointsValueSnapshot)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    choreRoomPill(chore.roomName)
                    if chore.status != .notStarted {
                        choreStatusPill(chore.status)
                    }
                }
            }
            .padding(.vertical, 11)
            .padding(.trailing, 11)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(chore.occurrence.titleSnapshot), \(chore.roomName), \(statusPresentation(chore.status).title)")
        }
        .background(choreRowBackground(chore.status), in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
    }

    private func choreBubbleIsChecked(_ status: ChoreOccurrenceStatus) -> Bool {
        status == .awaitingApproval || status == .completed
    }

    private func choreBubbleColor(_ status: ChoreOccurrenceStatus) -> Color {
        switch status {
        case .awaitingApproval:
            return HomeyTheme.warning
        case .completed:
            return HomeyTheme.success
        case .inProgress:
            return HomeyTheme.primary
        case .needsRedo, .cancelled:
            return HomeyTheme.danger
        case .notStarted, .skipped:
            return HomeyTheme.textSecondary
        }
    }

    private func choreRowBackground(_ status: ChoreOccurrenceStatus) -> Color {
        switch status {
        case .awaitingApproval:
            return HomeyTheme.warningSoft
        case .completed:
            return HomeyTheme.successSoft
        case .inProgress:
            return HomeyTheme.primarySoft
        case .needsRedo, .cancelled:
            return HomeyTheme.dangerSoft
        case .notStarted, .skipped:
            return HomeyTheme.surfacePrimary
        }
    }

    private func choreBubbleAccessibilityLabel(_ chore: MemberChoreRow) -> String {
        switch chore.status {
        case .awaitingApproval:
            return "\(chore.occurrence.titleSnapshot), pending approval. Uncheck unavailable"
        case .completed:
            return "\(chore.occurrence.titleSnapshot), done. Completion locked"
        case .notStarted, .inProgress, .needsRedo:
            return "Mark \(chore.occurrence.titleSnapshot) done"
        case .skipped:
            return "\(chore.occurrence.titleSnapshot), skipped"
        case .cancelled:
            return "\(chore.occurrence.titleSnapshot), cancelled"
        }
    }

    private func pointsPill(_ points: Int) -> some View {
        Text("\(points) pts")
            .font(.caption2.weight(.bold))
            .foregroundStyle(HomeyTheme.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(HomeyTheme.borderSubtle.opacity(0.48), in: Capsule())
    }

    private func choreRoomPill(_ roomName: String) -> some View {
        Label(roomName, systemImage: "house.fill")
            .font(.caption2.weight(.bold))
            .foregroundStyle(HomeyTheme.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(HomeyTheme.textSecondary.opacity(0.11), in: Capsule())
    }

    private func choreStatusPill(_ status: ChoreOccurrenceStatus) -> some View {
        let presentation = statusPresentation(status)
        return Label(presentation.title, systemImage: presentation.icon)
            .font(.caption2.weight(.bold))
            .foregroundStyle(presentation.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(presentation.color.opacity(0.11), in: Capsule())
    }

    private func statusPresentation(_ status: ChoreOccurrenceStatus) -> (title: String, icon: String, color: Color) {
        switch status {
        case .notStarted: return ("To Do", "circle", HomeyTheme.textSecondary)
        case .inProgress: return ("In Progress", "play.circle.fill", HomeyTheme.primary)
        case .awaitingApproval: return ("Awaiting Approval", "clock.fill", HomeyTheme.warning)
        case .completed: return ("Done", "checkmark.circle.fill", HomeyTheme.success)
        case .needsRedo: return ("Needs Redo", "arrow.counterclockwise.circle.fill", HomeyTheme.danger)
        case .skipped: return ("Skipped", "forward.end.fill", HomeyTheme.textSecondary)
        case .cancelled: return ("Cancelled", "xmark.circle.fill", HomeyTheme.danger)
        }
    }

    private func emptySection(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(HomeyTheme.textSecondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HomeyTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
    }

    private var emptyHousehold: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.3.fill")
                .font(.largeTitle)
                .foregroundStyle(HomeyTheme.primary)
            Text("No household members available")
                .font(.headline)
                .foregroundStyle(HomeyTheme.textPrimary)
            Text("Member columns will appear after this Home's members load.")
                .font(.subheadline)
                .foregroundStyle(HomeyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func refreshChoresHomeHub() async {
        reorderErrorMessage = nil
        refreshErrorMessage = nil
        homeService.membersErrorMessage = nil

        guard let refreshHomeID = homeID,
              let currentUser = authenticationService.currentUser else {
            await viewModel.refresh()
            return
        }

        let refreshDate = DailyTaskLocalDate.string(for: viewModel.selectedDate, timezone: timezone)

        async let memberRefresh: Void = homeService.refreshMembers(
            for: refreshHomeID,
            currentUser: currentUser
        )
        async let householdWorkRefresh: Void = viewModel.refresh()
        _ = await (memberRefresh, householdWorkRefresh)

        guard !Task.isCancelled,
              homeID == refreshHomeID,
              DailyTaskLocalDate.string(for: viewModel.selectedDate, timezone: timezone) == refreshDate else {
            return
        }

        synchronizeMemberOrder()
        if homeService.membersErrorMessage != nil || viewModel.errorMessage != nil {
            refreshErrorMessage = "We couldn't refresh all household tasks and chores."
        }
    }

    private func synchronizeMemberOrder() {
        guard homeService.selectedHomeID == homeID else {
            orderedMembers = []
            return
        }
        orderedMembers = homeService.membersForSelectedHome()
    }

    private func reorderMember(_ draggedMembershipID: UUID, relativeTo targetMembershipID: UUID) {
        guard canReorderMembers,
              !isPersistingMemberOrder,
              draggedMembershipID != targetMembershipID,
              let sourceIndex = orderedMembers.firstIndex(where: { $0.membershipId == draggedMembershipID }),
              let targetIndex = orderedMembers.firstIndex(where: { $0.membershipId == targetMembershipID }) else { return }

        var nextOrder = orderedMembers
        let member = nextOrder.remove(at: sourceIndex)
        nextOrder.insert(member, at: min(targetIndex, nextOrder.count))
        persistMemberOrder(nextOrder)
    }

    private func moveMember(_ membershipID: UUID, by offset: Int) {
        guard canReorderMembers,
              !isPersistingMemberOrder,
              let sourceIndex = orderedMembers.firstIndex(where: { $0.membershipId == membershipID }) else { return }
        let destinationIndex = sourceIndex + offset
        guard orderedMembers.indices.contains(destinationIndex) else { return }

        var nextOrder = orderedMembers
        nextOrder.swapAt(sourceIndex, destinationIndex)
        persistMemberOrder(nextOrder)
    }

    private func persistMemberOrder(_ nextOrder: [HomeMemberDisplay]) {
        guard let homeID,
              let currentUser = authenticationService.currentUser,
              Set(nextOrder.map(\.membershipId)).count == nextOrder.count,
              Set(nextOrder.map(\.membershipId)) == Set(orderedMembers.map(\.membershipId)) else { return }

        let previousOrder = orderedMembers
        orderedMembers = nextOrder
        reorderErrorMessage = nil
        isPersistingMemberOrder = true

        Task {
            let succeeded = await homeService.reorderMembers(
                homeID: homeID,
                membershipIDs: nextOrder.map(\.membershipId),
                currentUser: currentUser
            )

            if succeeded, homeService.selectedHomeID == homeID {
                orderedMembers = homeService.membersForSelectedHome()
            } else if self.homeID == homeID {
                orderedMembers = previousOrder
                reorderErrorMessage = "The member order couldn't be saved. The previous order was restored."
            }
            isPersistingMemberOrder = false
            if self.homeID != homeID {
                synchronizeMemberOrder()
            }
        }
    }

    private func memberColor(_ index: Int) -> Color {
        let colors = [
            HomeyTheme.lavender,
            HomeyTheme.success,
            HomeyTheme.peach,
            HomeyTheme.coral,
            HomeyTheme.primary
        ]
        return colors[index % colors.count]
    }
}
