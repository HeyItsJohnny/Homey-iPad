import SwiftUI
import Supabase
import Combine

struct AdminPendingChoreApproval: Decodable, Identifiable, Equatable, Sendable {
    let submissionID: UUID
    let occurrenceID: UUID
    let submittedBy: UUID
    let memberDisplayName: String
    let memberAvatarURL: String?
    let choreTitle: String
    let choreDescription: String?
    let roomName: String?
    let pointsValue: Int
    let submittedAt: Date
    let dueLocalDate: String?
    let requiresPhoto: Bool

    var id: UUID { submissionID }

    enum CodingKeys: String, CodingKey {
        case submissionID = "submission_id"
        case occurrenceID = "occurrence_id"
        case submittedBy = "submitted_by"
        case memberDisplayName = "member_display_name"
        case memberAvatarURL = "member_avatar_url"
        case choreTitle = "chore_title"
        case choreDescription = "chore_description"
        case roomName = "room_name"
        case pointsValue = "points_value"
        case submittedAt = "submitted_at"
        case dueLocalDate = "due_local_date"
        case requiresPhoto = "requires_photo"
    }
}

private enum AdminChoreReviewDecision: String {
    case approved
    case needsRedo = "needs_redo"
}

private enum AdminApprovalServiceError: LocalizedError {
    case sessionExpired
    case loadFailed
    case reviewFailed

    var errorDescription: String? {
        switch self {
        case .sessionExpired:
            return "Admin session expired. Enter a PIN to continue."
        case .loadFailed:
            return "Approvals could not be loaded. Please try again."
        case .reviewFailed:
            return "Chore could not be reviewed. Please try again."
        }
    }
}

private protocol AdminChoreApprovalServing {
    func pendingApprovals(homeID: UUID) async throws -> [AdminPendingChoreApproval]
    func review(homeID: UUID, sessionToken: String, submissionID: UUID, decision: AdminChoreReviewDecision, adminNote: String?) async throws -> UUID
}

private struct AdminChoreApprovalService: AdminChoreApprovalServing {
    private let client = SupabaseManager.shared.client

    func pendingApprovals(homeID: UUID) async throws -> [AdminPendingChoreApproval] {
        do {
            let approvals: [AdminPendingChoreApproval] = try await client.rpc(
                "get_pending_chore_approvals",
                params: AdminApprovalHomeParameters(homeID: homeID)
            ).execute().value
            return approvals
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw error
        }
    }

    func review(
        homeID: UUID,
        sessionToken: String,
        submissionID: UUID,
        decision: AdminChoreReviewDecision,
        adminNote: String? = nil
    ) async throws -> UUID {
        #if DEBUG
        print("[Homey] ADMIN APPROVAL REQUEST")
        print("submission_id: \(submissionID.uuidString)")
        print("decision: \(decision.rawValue)")
        print("home_id: \(homeID.uuidString)")
        #endif

        do {
            let approvalID: UUID = try await client.rpc(
                "review_chore_submission_with_admin_session",
                params: AdminChoreReviewParameters(
                    homeID: homeID,
                    sessionToken: sessionToken,
                    submissionID: submissionID,
                    decision: decision.rawValue,
                    adminNote: normalized(adminNote),
                    pointsAwarded: nil
                )
            ).execute().value

            #if DEBUG
            print("[Homey] ADMIN APPROVAL RPC SUCCESS")
            print("approval_id: \(approvalID.uuidString)")
            #endif
            return approvalID
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AdminApprovalServiceError {
            logMutationError(error)
            throw error
        } catch {
            logMutationError(error)
            let message = ((error as? PostgrestError)?.message ?? error.localizedDescription).lowercased()
            if message.contains("admin session") &&
                (message.contains("invalid") || message.contains("expired")) {
                throw AdminApprovalServiceError.sessionExpired
            }
            throw AdminApprovalServiceError.reviewFailed
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func logMutationError(_ error: Error) {
        #if DEBUG
        print("[Homey] ADMIN APPROVAL ERROR")
        print("type: \(String(reflecting: type(of: error)))")
        if let postgrestError = error as? PostgrestError {
            print("code: \(postgrestError.code ?? "")")
            print("message: \(postgrestError.message)")
            print("detail: \(postgrestError.detail ?? "")")
            print("hint: \(postgrestError.hint ?? "")")
        } else {
            print("code:")
            print("message: \(error.localizedDescription)")
            print("detail: \(String(reflecting: error))")
            print("hint:")
        }
        #endif
    }
}

private struct AdminApprovalHomeParameters: Encodable {
    let homeID: UUID

    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
    }
}

private struct AdminChoreReviewParameters: Encodable {
    let homeID: UUID
    let sessionToken: String
    let submissionID: UUID
    let decision: String
    let adminNote: String?
    let pointsAwarded: Int?

    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case sessionToken = "requested_session_token"
        case submissionID = "requested_submission_id"
        case decision = "requested_decision"
        case adminNote = "requested_admin_note"
        case pointsAwarded = "requested_points_awarded"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(homeID, forKey: .homeID)
        try container.encode(sessionToken, forKey: .sessionToken)
        try container.encode(submissionID, forKey: .submissionID)
        try container.encode(decision, forKey: .decision)
        try container.encodeIfPresent(adminNote, forKey: .adminNote)
        if adminNote == nil {
            try container.encodeNil(forKey: .adminNote)
        }
        try container.encodeNil(forKey: .pointsAwarded)
    }
}

@MainActor
private final class AdminApprovalsViewModel: ObservableObject {
    @Published private(set) var approvals: [AdminPendingChoreApproval] = []
    @Published private(set) var tripReviews: [AdminPendingTripReview] = []
    @Published private(set) var isLoading = false
    @Published private(set) var processingSubmissionIDs: Set<UUID> = []
    @Published private(set) var processingTripIDs: Set<UUID> = []
    @Published private(set) var loadErrorMessage: String?
    @Published private(set) var tripLoadErrorMessage: String?
    @Published private(set) var actionErrorMessage: String?

    private let service: any AdminChoreApprovalServing
    private let tripService: any AdminTripReviewServing
    private var activeHomeID: UUID?
    private var activeSessionToken: String?
    private var loadID = UUID()
    private var tripLoadID = UUID()
    private var globalLoadID = UUID()
    private var tripReviewEpoch = UUID()
    private var reviewedTripIDs: Set<UUID> = []

    init(service: (any AdminChoreApprovalServing)? = nil, tripService: (any AdminTripReviewServing)? = nil) {
        self.service = service ?? AdminChoreApprovalService()
        self.tripService = tripService ?? AdminTripReviewService()
    }

    var pendingCount: Int { approvals.count + tripReviews.count }

    func load(homeID: UUID, sessionToken: String, controller: HomeAdminAccessController, clearExisting: Bool = false) async {
        guard Self.controllerHasSession(controller, token: sessionToken), !Task.isCancelled else { return }
        if activeHomeID != homeID || activeSessionToken != sessionToken || clearExisting { reset() }
        activeHomeID = homeID
        activeSessionToken = sessionToken
        let requestID = UUID()
        globalLoadID = requestID
        loadID = requestID
        tripLoadID = requestID
        isLoading = true
        loadErrorMessage = nil
        tripLoadErrorMessage = nil
        actionErrorMessage = nil
        defer { if globalLoadID == requestID { isLoading = false } }

        async let chores = fetchChores(homeID: homeID)
        async let trips = fetchTrips(homeID: homeID)
        let (choreResult, tripResult) = await (chores, trips)
        guard isCurrentSession(homeID: homeID, token: sessionToken, controller: controller), !Task.isCancelled else { return }
        if case .failure(let error) = tripResult, AdminTripReviewError.isSessionExpiry(error) {
            reset(); controller.lock(); return
        }
        if case .failure(let error) = choreResult, AdminTripReviewError.isSessionExpiry(error) {
            reset(); controller.lock(); return
        }
        if loadID == requestID {
            switch choreResult {
            case .success(let rows): approvals = rows
            case .failure(let error):
                if !AdminTripReviewError.isCancellation(error) { loadErrorMessage = AdminApprovalServiceError.loadFailed.localizedDescription }
            }
        }
        if tripLoadID == requestID {
            switch tripResult {
            case .success(let rows): tripReviews = rows.filter { !reviewedTripIDs.contains($0.tripID) }
            case .failure(let error):
                if !AdminTripReviewError.isCancellation(error) { tripLoadErrorMessage = AdminTripReviewError.loadFailed.localizedDescription }
            }
        }
    }

    private func fetchChores(homeID: UUID) async -> Result<[AdminPendingChoreApproval], Error> {
        do { return .success(try await service.pendingApprovals(homeID: homeID)) }
        catch { return .failure(error) }
    }

    private func fetchTrips(homeID: UUID) async -> Result<[AdminPendingTripReview], Error> {
        do { return .success(try await tripService.pendingReviews(homeID: homeID)) }
        catch { return .failure(error) }
    }

    private static func controllerHasSession(_ controller: HomeAdminAccessController, token: String) -> Bool {
        guard case .unlocked(let session) = controller.state else { return false }
        return session.token == token && session.expiresAt > Date()
    }

    private func isCurrentSession(homeID: UUID, token: String, controller: HomeAdminAccessController) -> Bool {
        activeHomeID == homeID && activeSessionToken == token && Self.controllerHasSession(controller, token: token)
    }

    func review(
        _ approval: AdminPendingChoreApproval,
        decision: AdminChoreReviewDecision,
        homeID: UUID,
        sessionToken: String,
        controller: HomeAdminAccessController
    ) async {
        guard isCurrentSession(homeID: homeID, token: sessionToken, controller: controller),
              !Task.isCancelled,
              approvals.contains(where: { $0.submissionID == approval.submissionID }),
              !processingSubmissionIDs.contains(approval.submissionID) else {
            return
        }

        processingSubmissionIDs.insert(approval.submissionID)
        actionErrorMessage = nil
        defer { if activeSessionToken == sessionToken { processingSubmissionIDs.remove(approval.submissionID) } }

        do {
            _ = try await service.review(
                homeID: homeID,
                sessionToken: sessionToken,
                submissionID: approval.submissionID,
                decision: decision,
                adminNote: nil
            )
        } catch is CancellationError {
            return
        } catch AdminApprovalServiceError.sessionExpired {
            guard isCurrentSession(homeID: homeID, token: sessionToken, controller: controller) else { return }
            reset()
            controller.lock()
            return
        } catch {
            guard isCurrentSession(homeID: homeID, token: sessionToken, controller: controller) else { return }
            actionErrorMessage = error.localizedDescription
            return
        }

        NotificationCenter.default.post(name: .homeyChoresDidChange, object: nil)
        NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: nil)
        guard isCurrentSession(homeID: homeID, token: sessionToken, controller: controller) else { return }
        loadID = UUID()
        withAnimation(.easeInOut(duration: 0.2)) {
            approvals.removeAll { $0.submissionID == approval.submissionID }
        }
        controller.extendSessionAfterAdminActivity()
        await reconcileAfterSuccessfulReview(homeID: homeID, sessionToken: sessionToken, controller: controller)
    }

    private func reconcileAfterSuccessfulReview(homeID: UUID, sessionToken: String, controller: HomeAdminAccessController) async {
        let requestID = UUID()
        loadID = requestID

        do {
            let reconciledApprovals = try await service.pendingApprovals(homeID: homeID)
            guard isCurrentSession(homeID: homeID, token: sessionToken, controller: controller), loadID == requestID else { return }
            approvals = reconciledApprovals
        } catch is CancellationError {
            return
        } catch {
            if AdminTripReviewError.isSessionExpiry(error),
               isCurrentSession(homeID: homeID, token: sessionToken, controller: controller) {
                reset(); controller.lock(); return
            }
            #if DEBUG
            print("[Homey] ADMIN APPROVAL REFRESH ERROR")
            print("type: \(String(reflecting: type(of: error)))")
            if let postgrestError = error as? PostgrestError {
                print("code: \(postgrestError.code ?? "")")
                print("message: \(postgrestError.message)")
                print("detail: \(postgrestError.detail ?? "")")
                print("hint: \(postgrestError.hint ?? "")")
            } else {
                print("code:")
                print("message: \(error.localizedDescription)")
                print("detail: \(String(reflecting: error))")
                print("hint:")
            }
            #endif
        }
    }


    func submitTripReview(_ trip: AdminPendingTripReview, draft: AdminTripReviewDraft, homeID: UUID,
                          sessionToken: String, controller: HomeAdminAccessController) async {
        guard isCurrentSession(homeID: homeID, token: sessionToken, controller: controller),
              !Task.isCancelled, draft.isValid, !processingTripIDs.contains(trip.tripID),
              tripReviews.contains(where: { $0.tripID == trip.tripID }) else { return }
        let epoch = tripReviewEpoch
        processingTripIDs.insert(trip.tripID)
        actionErrorMessage = nil
        defer { if activeSessionToken == sessionToken, tripReviewEpoch == epoch { processingTripIDs.remove(trip.tripID) } }

        do {
            _ = try await tripService.submit(homeID: homeID, sessionToken: sessionToken, tripID: trip.tripID, draft: draft)
        } catch is CancellationError {
            return
        } catch AdminTripReviewError.sessionExpired {
            guard tripReviewEpoch == epoch, isCurrentSession(homeID: homeID, token: sessionToken, controller: controller) else { return }
            reset()
            controller.lock()
            return
        } catch {
            guard tripReviewEpoch == epoch, isCurrentSession(homeID: homeID, token: sessionToken, controller: controller) else { return }
            actionErrorMessage = error.localizedDescription
            return
        }

        guard tripReviewEpoch == epoch, isCurrentSession(homeID: homeID, token: sessionToken, controller: controller) else { return }
        tripLoadID = UUID()
        reviewedTripIDs.insert(trip.tripID)
        withAnimation(.easeInOut(duration: 0.2)) {
            tripReviews.removeAll { $0.tripID == trip.tripID }
        }
        controller.extendSessionAfterAdminActivity()
        // Reconciliation has its own failure path; the successful review stays removed.
        await reconcileTripsAfterSuccess(homeID: homeID, token: sessionToken, controller: controller)
    }

    func invalidateTripReviews(homeID: UUID, token: String, controller: HomeAdminAccessController) async {
        guard isCurrentSession(homeID: homeID, token: token, controller: controller) else { return }
        tripReviewEpoch = UUID()
        tripLoadID = UUID()
        tripReviews = []
        processingTripIDs = []
        reviewedTripIDs = []
        tripLoadErrorMessage = nil
        await reconcileTripsAfterSuccess(homeID: homeID, token: token, controller: controller)
    }

    private func reconcileTripsAfterSuccess(homeID: UUID, token: String, controller: HomeAdminAccessController) async {
        let requestID = UUID()
        tripLoadID = requestID
        do {
            let rows = try await tripService.pendingReviews(homeID: homeID)
            guard isCurrentSession(homeID: homeID, token: token, controller: controller), tripLoadID == requestID else { return }
            tripReviews = rows.filter { !reviewedTripIDs.contains($0.tripID) }
            tripLoadErrorMessage = nil
        } catch is CancellationError {
        } catch AdminTripReviewError.sessionExpired {
            guard isCurrentSession(homeID: homeID, token: token, controller: controller) else { return }
            reset(); controller.lock()
        } catch {
            guard isCurrentSession(homeID: homeID, token: token, controller: controller), tripLoadID == requestID else { return }
            tripLoadErrorMessage = AdminTripReviewError.loadFailed.localizedDescription
        }
    }

    func reset() {
        activeHomeID = nil
        activeSessionToken = nil
        tripReviewEpoch = UUID()
        loadID = UUID()
        tripLoadID = UUID()
        globalLoadID = UUID()
        approvals = []
        tripReviews = []
        reviewedTripIDs = []
        processingSubmissionIDs = []
        processingTripIDs = []
        isLoading = false
        loadErrorMessage = nil
        tripLoadErrorMessage = nil
        actionErrorMessage = nil
    }
}

struct AdminApprovalsView: View {
    @EnvironmentObject private var homeService: HomeService
    let homeID: UUID
    let session: HomeAdminSession
    @ObservedObject var controller: HomeAdminAccessController
    @StateObject private var viewModel = AdminApprovalsViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                approvalsHeader

                if let message = viewModel.loadErrorMessage { errorBanner(message) }
                if let message = viewModel.tripLoadErrorMessage { errorBanner(message) }
                if let message = viewModel.actionErrorMessage { errorBanner(message) }

                if viewModel.isLoading && viewModel.pendingCount == 0 {
                    loadingState
                } else if viewModel.pendingCount == 0 {
                    if viewModel.loadErrorMessage != nil || viewModel.tripLoadErrorMessage != nil {
                        loadErrorState("Some reviews could not be loaded. Please try again.")
                    } else {
                        emptyState
                    }
                }
                if !viewModel.approvals.isEmpty {
                    queueHeading("CHORE APPROVALS", count: viewModel.approvals.count)
                    ForEach(viewModel.approvals) { approval in
                        AdminApprovalCard(
                            approval: approval,
                            isProcessing: viewModel.processingSubmissionIDs.contains(approval.submissionID),
                            onNeedsMoreWork: { review(approval, decision: .needsRedo) },
                            onApprove: { review(approval, decision: .approved) }
                        )
                    }
                }
                if !viewModel.tripReviews.isEmpty {
                    queueHeading("TRIPS TO REVIEW", count: viewModel.tripReviews.count)
                    ForEach(viewModel.tripReviews) { trip in
                        AdminTripReviewCard(
                            trip: trip,
                            timezone: homeService.selectedHome()?.timezone.flatMap(TimeZone.init(identifier:)) ?? .current,
                            isProcessing: viewModel.processingTripIDs.contains(trip.tripID),
                            onSubmit: { draft in submitTripReview(trip, draft: draft) }
                        )
                    }
                }
            }
            .padding(4)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await viewModel.load(homeID: homeID, sessionToken: session.token, controller: controller)
        }
        .task(id: "\(homeID)-\(session.token)") {
            await viewModel.load(homeID: homeID, sessionToken: session.token, controller: controller, clearExisting: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: TripsResetNotice.name)) { notice in
            guard let affectedHomeID = notice.object as? UUID, affectedHomeID == homeID,
                  homeService.selectedHomeID == homeID else { return }
            Task { await viewModel.invalidateTripReviews(homeID: homeID, token: session.token, controller: controller) }
        }
        .onChange(of: controller.state) { _, state in
            if case .unlocked(let active) = state, active.token == session.token { return }
            viewModel.reset()
        }
        .onChange(of: homeService.selectedHomeID) { _, id in
            if id != homeID { viewModel.reset() }
        }
        .onDisappear {
            viewModel.reset()
        }
    }

    private var approvalsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Approvals", systemImage: "checkmark.seal.fill")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(HomeyTheme.textPrimary)

            Spacer()

            Text("\(viewModel.pendingCount) Pending")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyTheme.primary)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(HomeyTheme.primarySoft, in: Capsule())
        }
    }

    private func queueHeading(_ title: String, count: Int) -> some View {
        Text("\(title) · \(count)")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(HomeyTheme.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func submitTripReview(_ trip: AdminPendingTripReview, draft: AdminTripReviewDraft) {
        guard homeService.selectedHomeID == homeID else { return }
        Task {
            guard homeService.selectedHomeID == homeID else { return }
            await viewModel.submitTripReview(trip, draft: draft, homeID: homeID, sessionToken: session.token, controller: controller)
        }
    }

    private var loadingState: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(HomeyTheme.primary)
            Text("Loading approvals…")
                .font(.headline)
                .foregroundStyle(HomeyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .dashboardCard(cornerRadius: HomeyRadius.page)
    }

    private func loadErrorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(HomeyTheme.danger)
            Text(message)
                .font(.headline)
                .foregroundStyle(HomeyTheme.textPrimary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await viewModel.load(homeID: homeID, sessionToken: session.token, controller: controller) }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(minHeight: 48)
            .background(HomeyTheme.primary, in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(28)
        .dashboardCard(cornerRadius: HomeyRadius.page)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(HomeyTheme.success)
            Text("All caught up!")
                .font(.title2.bold())
                .foregroundStyle(HomeyTheme.textPrimary)
            Text("Nothing is waiting for review.")
                .font(.title3)
                .foregroundStyle(HomeyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(28)
        .dashboardCard(cornerRadius: HomeyRadius.page)
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(HomeyTheme.danger)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HomeyTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
    }

    private func review(_ approval: AdminPendingChoreApproval, decision: AdminChoreReviewDecision) {
        guard homeService.selectedHomeID == homeID else { return }
        Task {
            guard homeService.selectedHomeID == homeID else { return }
            await viewModel.review(
                approval,
                decision: decision,
                homeID: homeID,
                sessionToken: session.token,
                controller: controller
            )
        }
    }
}

private struct AdminApprovalCard: View {
    let approval: AdminPendingChoreApproval
    let isProcessing: Bool
    let onNeedsMoreWork: () -> Void
    let onApprove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                AvatarView(
                    imageURL: approval.memberAvatarURL.flatMap(URL.init(string:)),
                    initials: initials,
                    size: 58,
                    accessibilityLabel: "\(approval.memberDisplayName) avatar"
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(approval.choreTitle)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(HomeyTheme.textPrimary)
                        .lineLimit(2)

                    Text(approvalMetadata)
                        .font(.headline)
                        .foregroundStyle(HomeyTheme.textSecondary)
                        .lineLimit(1)

                    if let description = normalized(approval.choreDescription) {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(HomeyTheme.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 18)

                Text("\(approval.pointsValue) pts")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyTheme.primary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(HomeyTheme.primarySoft, in: Capsule())
            }

            HStack(spacing: 18) {
                Label(submittedText, systemImage: "clock.fill")

                if approval.requiresPhoto {
                    Label("Photo Required", systemImage: "camera.fill")
                        .foregroundStyle(HomeyTheme.peach)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(HomeyTheme.textSecondary)

            HStack(spacing: 14) {
                Button(action: onNeedsMoreWork) {
                    Label("Needs More Work", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .font(.headline)
                .foregroundStyle(HomeyTheme.danger)
                .frame(minHeight: 54)
                .background(HomeyTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
                        .stroke(HomeyTheme.danger.opacity(0.30), lineWidth: 1)
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)

                Button(action: onApprove) {
                    HStack(spacing: 9) {
                        if isProcessing {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark.seal.fill")
                        }
                        Text(isProcessing ? "Reviewing…" : "Approve")
                    }
                    .frame(maxWidth: .infinity)
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(minHeight: 54)
                .background(HomeyTheme.primary, in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
                .buttonStyle(.plain)
                .disabled(isProcessing)
            }
        }
        .padding(24)
        .dashboardCard(cornerRadius: HomeyRadius.page)
        .opacity(isProcessing ? 0.82 : 1)
    }

    private var initials: String {
        let parts = approval.memberDisplayName.split(separator: " ")
        return parts.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private var approvalMetadata: String {
        var segments = [approval.memberDisplayName]
        if let room = normalized(approval.roomName) {
            segments.append(room)
        }
        if let scheduledDate = scheduledDateText {
            segments.append("Scheduled \(scheduledDate)")
        }
        return segments.joined(separator: " • ")
    }

    private var scheduledDateText: String? {
        guard let dueLocalDate = normalized(approval.dueLocalDate) else { return nil }
        let components = dueLocalDate.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0].count == 4,
              components[1].count == 2,
              components[2].count == 2,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2]),
              (1...12).contains(month),
              (1...31).contains(day) else {
            return nil
        }
        return String(format: "%02d/%02d/%04d", month, day, year)
    }

    private var submittedText: String {
        "Submitted \(approval.submittedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
