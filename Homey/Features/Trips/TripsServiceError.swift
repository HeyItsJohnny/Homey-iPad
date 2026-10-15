import Foundation

enum TripsServiceError: LocalizedError {
    case missingTitle
    var errorDescription: String? { "Enter a Trip title." }
}

