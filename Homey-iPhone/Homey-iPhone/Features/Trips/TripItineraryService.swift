import Foundation
import Supabase

struct TripItineraryService {
    private let client = SupabaseManager.shared.client

    func itinerary(tripID: UUID) async throws -> [TripItineraryItem] {
        do {
            return try await client.rpc(
                "get_trip_itinerary",
                params: TripItineraryTripParameters(tripID: tripID)
            ).execute().value
        } catch {
            if Self.isCancellation(error) { throw CancellationError() }
            Self.log(error, operation: "get_trip_itinerary", id: tripID)
            throw TripItineraryError.refreshFailed
        }
    }

    func save(
        tripID: UUID,
        itemID: UUID?,
        draft: TripItineraryDraft,
        sortOrder: Int
    ) async throws {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw TripItineraryError.missingTitle }
        if draft.includesStartTime,
           draft.includesEndTime,
           Calendar.current.compare(draft.endTime, to: draft.startTime, toGranularity: .minute) != .orderedDescending {
            throw TripItineraryError.invalidTimeRange
        }

        let input = TripItinerarySaveInput(
            itemDate: TripDateFormatters.backendString(from: draft.itemDate),
            startTime: draft.includesStartTime ? TripTimeFormatters.backendString(from: draft.startTime) : nil,
            endTime: draft.includesEndTime ? TripTimeFormatters.backendString(from: draft.endTime) : nil,
            title: title,
            locationName: Self.trimmed(draft.locationName),
            locationAddress: Self.trimmed(draft.locationAddress),
            notes: Self.trimmed(draft.notes),
            sortOrder: sortOrder
        )
        try await save(tripID: tripID, itemID: itemID, input: input)
    }

    func saveExisting(_ item: TripItineraryItem, sortOrder: Int) async throws {
        let input = TripItinerarySaveInput(
            itemDate: TripDateFormatters.backendDate.string(from: item.itemDate),
            startTime: item.startTime,
            endTime: item.endTime,
            title: item.title,
            locationName: item.locationName,
            locationAddress: item.locationAddress,
            notes: item.notes,
            sortOrder: sortOrder
        )
        try await save(tripID: item.tripID, itemID: item.id, input: input)
    }

    func remove(tripID: UUID, itemID: UUID) async throws {
        do {
            try await client.rpc(
                "delete_trip_itinerary_item",
                params: DeleteTripItineraryItemParameters(tripID: tripID, itemID: itemID)
            ).execute()
        } catch {
            if Self.isCancellation(error) { throw CancellationError() }
            Self.log(error, operation: "delete_trip_itinerary_item", id: itemID)
            throw TripItineraryError.removeFailed
        }
    }

    private func save(tripID: UUID, itemID: UUID?, input: TripItinerarySaveInput) async throws {
        do {
            try await client.rpc(
                "save_trip_itinerary_item",
                params: SaveTripItineraryItemParameters(tripID: tripID, itemID: itemID, input: input)
            ).execute()
        } catch {
            if Self.isCancellation(error) { throw CancellationError() }
            Self.log(error, operation: "save_trip_itinerary_item", id: itemID ?? tripID)
            throw TripItineraryError.saveFailed
        }
    }

    private static func trimmed(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let value = error as NSError
        if value.domain == NSURLErrorDomain, value.code == NSURLErrorCancelled { return true }
        if let underlying = value.userInfo[NSUnderlyingErrorKey] as? Error {
            return isCancellation(underlying)
        }
        return false
    }

    private static func log(_ error: Error, operation: String, id: UUID) {
        #if DEBUG
        print("[Homey Trips Itinerary] \(operation) id=\(id.uuidString) error=\(String(reflecting: error))")
        #endif
    }
}

enum TripItineraryError: LocalizedError {
    case refreshFailed
    case missingTitle
    case invalidDate
    case invalidTimeRange
    case saveFailed
    case removeFailed

    var errorDescription: String? {
        switch self {
        case .refreshFailed: "Itinerary could not be refreshed."
        case .missingTitle: "Enter an activity name."
        case .invalidDate: "Choose a date within the trip."
        case .invalidTimeRange: "End time must be after the start time."
        case .saveFailed: "Activity could not be saved."
        case .removeFailed: "Activity could not be removed."
        }
    }
}

private struct TripItinerarySaveInput {
    let itemDate: String
    let startTime: String?
    let endTime: String?
    let title: String
    let locationName: String?
    let locationAddress: String?
    let notes: String?
    let sortOrder: Int
}

private struct TripItineraryTripParameters: Encodable {
    let tripID: UUID
    enum CodingKeys: String, CodingKey { case tripID = "requested_trip_id" }
}

private struct DeleteTripItineraryItemParameters: Encodable {
    let tripID: UUID
    let itemID: UUID
    enum CodingKeys: String, CodingKey {
        case tripID = "requested_trip_id"
        case itemID = "requested_item_id"
    }
}

private struct SaveTripItineraryItemParameters: Encodable {
    let tripID: UUID
    let itemID: UUID?
    let input: TripItinerarySaveInput

    enum CodingKeys: String, CodingKey {
        case tripID = "requested_trip_id"
        case itemID = "requested_item_id"
        case itemDate = "requested_item_date"
        case startTime = "requested_start_time"
        case endTime = "requested_end_time"
        case title = "requested_title"
        case locationName = "requested_location_name"
        case locationAddress = "requested_location_address"
        case notes = "requested_notes"
        case sortOrder = "requested_sort_order"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tripID, forKey: .tripID)
        try container.encodeItineraryOptional(itemID, forKey: .itemID)
        try container.encode(input.itemDate, forKey: .itemDate)
        try container.encodeItineraryOptional(input.startTime, forKey: .startTime)
        try container.encodeItineraryOptional(input.endTime, forKey: .endTime)
        try container.encode(input.title, forKey: .title)
        try container.encodeItineraryOptional(input.locationName, forKey: .locationName)
        try container.encodeItineraryOptional(input.locationAddress, forKey: .locationAddress)
        try container.encodeItineraryOptional(input.notes, forKey: .notes)
        try container.encode(input.sortOrder, forKey: .sortOrder)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeItineraryOptional<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
