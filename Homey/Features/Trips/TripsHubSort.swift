import Foundation

enum TripsHubSort {
    static func ideas(_ values: [SavedTripIdea]) -> [SavedTripIdea] {
        values.sorted { alphabetical($0.title, $0.id, $1.title, $1.id) }
    }
    static func planned(_ values: [Trip]) -> [Trip] {
        values.filter { $0.status == .planned || $0.status == .active }.sorted {
            switch ($0.startDate, $1.startDate) {
            case let (a?, b?) where a != b: return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return alphabetical($0.title, $0.id, $1.title, $1.id)
            }
        }
    }
    static func past(_ values: [Trip]) -> [Trip] {
        values.filter { $0.status == .completed }.sorted {
            switch ($0.endDate ?? $0.startDate, $1.endDate ?? $1.startDate) {
            case let (a?, b?) where a != b: return a > b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return alphabetical($0.title, $0.id, $1.title, $1.id)
            }
        }
    }
    private static func alphabetical(_ a: String, _ aid: UUID, _ b: String, _ bid: UUID) -> Bool {
        let result = a.caseInsensitiveCompare(b)
        return result == .orderedSame ? aid.uuidString < bid.uuidString : result == .orderedAscending
    }
}

