import Foundation

enum ProfileNameFormatter {
    static let requiredDisplayNameMessage = "Display Name is required."

    static func generatedDisplayName(firstName: String, lastName: String) -> String {
        [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Call only after a user changes First Name or Last Name, never on load or
    /// in response to editing/clearing Display Name itself.
    static func displayNameAfterNameChange(displayName: String, firstName: String, lastName: String) -> String {
        guard displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return displayName }
        return generatedDisplayName(firstName: firstName, lastName: lastName)
    }

    static func displayNameError(_ displayName: String) -> String? {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? requiredDisplayNameMessage : nil
    }
}

struct NormalizedProfileInput {
    let firstName: String?
    let lastName: String?
    let displayName: String?

    init(firstName: String, lastName: String, displayName: String) {
        self.firstName = Self.normalized(firstName)
        self.lastName = Self.normalized(lastName)
        self.displayName = Self.normalized(displayName)
    }

    private static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
