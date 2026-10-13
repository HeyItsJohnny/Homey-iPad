import SwiftUI
import UIKit

struct TripHouseholdInviteView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    let homeID: UUID
    let invite: TripHouseholdInvite
    @State private var isRevoking = false
    @State private var errorMessage: String?
    @State private var revokeTask: Task<Void, Never>?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Invite another household").font(.title2.bold())
                Text(trip.title).font(.headline)
                Text("CODE").font(.caption.weight(.semibold))
                Text(invite.code)
                    .font(.largeTitle.monospaced().bold())
                    .textSelection(.enabled)
                Text(TripInviteDates.expiration(invite.expiresAt))
                    .foregroundStyle(HomeyColors.secondaryText)
                Button(copied ? "Copied" : "Copy Code") {
                    UIPasteboard.general.string = invite.code
                    copied = true
                }
                .buttonStyle(HomeyButtonStyle(secondary: true))
                ShareLink(item: "Join our Homey trip: \(trip.title)\n\nTrip Invite Code: \(invite.code)") {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(HomeyButtonStyle())
                if canManage {
                    Button("Revoke Invite", role: .destructive, action: revoke)
                        .disabled(isRevoking)
                }
                if isRevoking { ProgressView() }
                if let errorMessage { HomeyErrorView(message: errorMessage) }
                Spacer()
            }
            .padding(24)
            .navigationTitle("Trip Invitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(isRevoking)
                }
            }
            .disabled(!canManage || isRevoking)
        }
        .interactiveDismissDisabled(isRevoking)
        .onChange(of: session.activeHome?.id) { _, id in
            if id != homeID { revokeTask?.cancel(); dismiss() }
        }
        .onChange(of: session.activeRole) { _, _ in
            if !canManage { revokeTask?.cancel(); dismiss() }
        }
        .onDisappear { revokeTask?.cancel() }
    }

    private var canManage: Bool {
        session.activeHome?.id == homeID && homeID == trip.organizerHomeID && session.activeRole?.canManageInvitations == true
    }

    private func revoke() {
        guard !isRevoking, canManage, !session.isSwitchingHome else { return }
        isRevoking = true
        errorMessage = nil
        revokeTask = Task { @MainActor in
            defer { isRevoking = false }
            do {
                try Task.checkCancellation()
                guard canManage else { return }
                try await TripPeopleService().revokeInvite(tripID: trip.id)
                dismiss()
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, canManage else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
