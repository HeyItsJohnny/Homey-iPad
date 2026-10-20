import SwiftUI

struct ChoreOccurrenceStatusStyle: Equatable {
    let title: String
    let color: Color
    let backgroundColor: Color

    init(occurrence: ChoreOccurrence) {
        self.init(displayStatus: occurrence.displayStatus)
    }

    init(displayStatus: ChoreOccurrenceDisplayStatus) {
        switch displayStatus {
        case .overdue:
            title = "Overdue"
            color = HomeyTheme.danger
            backgroundColor = color.opacity(0.12)
        case .stored(let status):
            switch status {
            case .notStarted:
                title = "Not Started"
                color = HomeyTheme.choreRemaining
                backgroundColor = HomeyTheme.surfaceSecondary
            case .inProgress:
                title = "In Progress"
                color = HomeyTheme.primary
                backgroundColor = HomeyTheme.primarySoft
            case .awaitingApproval:
                title = "Pending Approval"
                color = HomeyTheme.warning
                backgroundColor = color.opacity(0.12)
            case .completed:
                title = "Approved"
                color = HomeyTheme.success
                backgroundColor = color.opacity(0.12)
            case .needsRedo:
                title = "Needs Redo"
                color = HomeyTheme.danger
                backgroundColor = color.opacity(0.12)
            case .skipped:
                title = "Skipped"
                color = HomeyTheme.textSecondary
                backgroundColor = HomeyTheme.surfacePrimary
            case .cancelled:
                title = "Cancelled"
                color = HomeyTheme.danger
                backgroundColor = HomeyTheme.dangerSoft
            }
        }
    }
}
