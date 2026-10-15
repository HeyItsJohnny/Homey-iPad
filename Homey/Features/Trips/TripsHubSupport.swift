import Foundation
import Combine

@MainActor
final class TripsHubModel: ObservableObject {
    @Published var ideas: [SavedTripIdea] = []
    @Published var trips: [Trip] = []
    @Published var error: String?
    @Published var loading = false
    private var homeID: UUID?
    private var loadID = UUID()
    func load(_ home: UUID?) async {
        let token = UUID(); loadID = token
        if homeID != home { ideas = []; trips = [] }
        homeID = home
        guard let home else { loading = false; return }
        loading = true; error = nil
        defer { if loadID == token { loading = false } }
        do {
            async let saved = Trips2Service().savedIdeas(homeID: home)
            async let visits = Trips2Service().trips(homeID: home)
            let (s, t) = try await (saved, visits)
            guard loadID == token, !Task.isCancelled else { return }
            ideas = TripsHubSort.ideas(s.filter { $0.homeID == home }); trips = t
        } catch {
            guard loadID == token, !Task.isCancelled else { return }
            self.error = "Trips could not be loaded. Please try again."
        }
    }
}

