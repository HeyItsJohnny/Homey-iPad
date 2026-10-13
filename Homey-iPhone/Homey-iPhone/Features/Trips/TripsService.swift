import Foundation
import Supabase

struct TripsService {
    private let client = SupabaseManager.shared.client

    func trips(homeID: UUID) async throws -> [Trip] {
        try await client.rpc(
            "get_home_trips",
            params: TripsHomeParameters(homeID: homeID)
        ).execute().value
    }

    func create(homeID: UUID, draft: TripEditorDraft, mode: TripEditorMode) async throws {
        let input = try normalized(draft: draft, mode: mode)
        do {
            try await client.rpc(
                "create_trip",
                params: CreateTripParameters(homeID: homeID, input: input)
            ).execute()
        } catch {
            if Self.isCancellation(error) { throw CancellationError() }
            Self.log(error, operation: "create_trip", id: homeID)
            throw TripsServiceError.createFailed
        }
    }

    func update(tripID: UUID, draft: TripEditorDraft, mode: TripEditorMode) async throws {
        let input = try normalized(draft: draft, mode: mode)
        do {
            try await client.rpc(
                "update_trip",
                params: UpdateTripParameters(tripID: tripID, input: input)
            ).execute()
        } catch {
            if Self.isCancellation(error) { throw CancellationError() }
            Self.log(error, operation: "update_trip", id: tripID)
            throw TripsServiceError.updateFailed
        }
    }

    /// The backend owns cascade cleanup; independent Calendar events and cloned Trips stay intact.
    func delete(tripID: UUID) async throws {
        do {
            try Task.checkCancellation()
            try await client.rpc(
                "delete_trip",
                params: DeleteTripParameters(tripID: tripID)
            ).execute()
        } catch {
            if Self.isCancellation(error) || Task.isCancelled { throw CancellationError() }
            Self.log(error, operation: "delete_trip", id: tripID)
            throw TripsServiceError.deleteFailed
        }
    }

    func complete(tripID: UUID) async throws {
        do {
            try Task.checkCancellation()
            try await client.rpc(
                "complete_trip",
                params: CompleteTripParameters(tripID: tripID)
            ).execute()
        } catch {
            if Self.isCancellation(error) || Task.isCancelled { throw CancellationError() }
            Self.log(error, operation: "complete_trip", id: tripID)
            throw TripsServiceError.completeFailed
        }
    }

    /// Cloning belongs to the backend; send only the original ID and new schedule.
    func planAgain(tripID: UUID, schedule: TripPlanAgainDraft) async throws -> UUID {
        guard schedule.endDate >= schedule.startDate else {
            throw TripsServiceError.invalidDateRange
        }
        if schedule.includesTimes,
           Calendar.current.isDate(schedule.startDate, inSameDayAs: schedule.endDate),
           Calendar.current.compare(schedule.endTime, to: schedule.startTime, toGranularity: .minute) != .orderedDescending {
            throw TripsServiceError.invalidTimeRange
        }
        try Task.checkCancellation()
        do {
            return try await client.rpc(
                "plan_trip_again",
                params: PlanTripAgainParameters(
                    tripID: tripID,
                    startDate: TripDateFormatters.backendString(from: schedule.startDate),
                    endDate: TripDateFormatters.backendString(from: schedule.endDate),
                    startTime: schedule.includesTimes ? TripTimeFormatters.backendString(from: schedule.startTime) : nil,
                    endTime: schedule.includesTimes ? TripTimeFormatters.backendString(from: schedule.endTime) : nil
                )
            ).execute().value
        } catch {
            if Self.isCancellation(error) { throw CancellationError() }
            Self.log(error, operation: "plan_trip_again", id: tripID)
            throw TripsServiceError.planAgainFailed
        }
    }

    private func normalized(draft: TripEditorDraft, mode: TripEditorMode) throws -> NormalizedTripInput {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw TripsServiceError.missingTitle }

        guard mode.showsSchedule else {
            return NormalizedTripInput(
                title: title,
                destinationName: Self.trimmed(draft.destinationName),
                destinationAddress: Self.trimmed(draft.destinationAddress),
                status: mode.status,
                durationType: draft.durationType,
                startDate: nil,
                endDate: nil,
                startTime: nil,
                endTime: nil,
                estimatedDriveMinutes: nil,
                notes: Self.trimmed(draft.notes)
            )
        }

        let calendar = Calendar.current
        let startDate = TripDateFormatters.localNoon(draft.startDate)
        var endDate = TripDateFormatters.localNoon(draft.endDate)
        if draft.durationType == .fewHours || draft.durationType == .dayTrip {
            endDate = startDate
        }
        guard calendar.compare(endDate, to: startDate, toGranularity: .day) != .orderedAscending else {
            throw TripsServiceError.invalidDateRange
        }
        let usesTime = draft.durationType == .fewHours ||
            ((draft.durationType == .dayTrip || draft.durationType == .custom) && draft.includesTimes)
        if usesTime,
           calendar.isDate(startDate, inSameDayAs: endDate),
           calendar.compare(draft.endTime, to: draft.startTime, toGranularity: .minute) != .orderedDescending {
            throw TripsServiceError.invalidTimeRange
        }
        let driveMinutes = max(0, draft.estimatedDriveHours) * 60 + max(0, draft.estimatedDriveMinutes)

        return NormalizedTripInput(
            title: title,
            destinationName: Self.trimmed(draft.destinationName),
            destinationAddress: Self.trimmed(draft.destinationAddress),
            status: mode.status,
            durationType: draft.durationType,
            startDate: TripDateFormatters.backendString(from: startDate),
            endDate: TripDateFormatters.backendString(from: endDate),
            startTime: usesTime ? TripTimeFormatters.backendString(from: draft.startTime) : nil,
            endTime: usesTime ? TripTimeFormatters.backendString(from: draft.endTime) : nil,
            estimatedDriveMinutes: driveMinutes > 0 ? driveMinutes : nil,
            notes: Self.trimmed(draft.notes)
        )
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
        print("[Homey Trips] \(operation) id=\(id.uuidString) error=\(String(reflecting: error))")
        #endif
    }
}

enum TripsServiceError: LocalizedError {
    case missingTitle
    case invalidDateRange
    case invalidTimeRange
    case createFailed
    case updateFailed
    case planAgainFailed
    case completeFailed
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .missingTitle: "Enter a trip name."
        case .invalidDateRange: "End date must be on or after the start date."
        case .invalidTimeRange: "End time must be after the start time."
        case .createFailed: "Trip could not be saved."
        case .updateFailed: "Trip could not be updated."
        case .planAgainFailed: "Trip could not be planned again."
        case .completeFailed: "Trip could not be completed."
        case .deleteFailed: "Trip could not be deleted."
        }
    }
}

private struct NormalizedTripInput {
    let title: String
    let destinationName: String?
    let destinationAddress: String?
    let status: TripStatus
    let durationType: TripDurationType
    let startDate: String?
    let endDate: String?
    let startTime: String?
    let endTime: String?
    let estimatedDriveMinutes: Int?
    let notes: String?
}

private struct CreateTripParameters: Encodable {
    let homeID: UUID
    let input: NormalizedTripInput

    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case title = "requested_title"
        case destinationName = "requested_destination_name"
        case destinationAddress = "requested_destination_address"
        case status = "requested_status"
        case durationType = "requested_duration_type"
        case startDate = "requested_start_date"
        case endDate = "requested_end_date"
        case startTime = "requested_start_time"
        case endTime = "requested_end_time"
        case estimatedDriveMinutes = "requested_estimated_drive_minutes"
        case notes = "requested_notes"
        case sourceType = "requested_source_type"
        case sourceURL = "requested_source_url"
        case sourceTitle = "requested_source_title"
        case sourceText = "requested_source_text"
        case sourceImageURL = "requested_source_image_url"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(homeID, forKey: .homeID)
        try container.encode(input.title, forKey: .title)
        try container.encodeOptional(input.destinationName, forKey: .destinationName)
        try container.encodeOptional(input.destinationAddress, forKey: .destinationAddress)
        try container.encode(input.status, forKey: .status)
        try container.encode(input.durationType, forKey: .durationType)
        try container.encodeOptional(input.startDate, forKey: .startDate)
        try container.encodeOptional(input.endDate, forKey: .endDate)
        try container.encodeOptional(input.startTime, forKey: .startTime)
        try container.encodeOptional(input.endTime, forKey: .endTime)
        try container.encodeOptional(input.estimatedDriveMinutes, forKey: .estimatedDriveMinutes)
        try container.encodeOptional(input.notes, forKey: .notes)
        try container.encodeNil(forKey: .sourceType)
        try container.encodeNil(forKey: .sourceURL)
        try container.encodeNil(forKey: .sourceTitle)
        try container.encodeNil(forKey: .sourceText)
        try container.encodeNil(forKey: .sourceImageURL)
    }
}

private struct UpdateTripParameters: Encodable {
    let tripID: UUID
    let input: NormalizedTripInput

    enum CodingKeys: String, CodingKey {
        case tripID = "requested_trip_id"
        case title = "requested_title"
        case destinationName = "requested_destination_name"
        case destinationAddress = "requested_destination_address"
        case status = "requested_status"
        case durationType = "requested_duration_type"
        case startDate = "requested_start_date"
        case endDate = "requested_end_date"
        case startTime = "requested_start_time"
        case endTime = "requested_end_time"
        case estimatedDriveMinutes = "requested_estimated_drive_minutes"
        case notes = "requested_notes"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tripID, forKey: .tripID)
        try container.encode(input.title, forKey: .title)
        try container.encodeOptional(input.destinationName, forKey: .destinationName)
        try container.encodeOptional(input.destinationAddress, forKey: .destinationAddress)
        try container.encode(input.status, forKey: .status)
        try container.encode(input.durationType, forKey: .durationType)
        try container.encodeOptional(input.startDate, forKey: .startDate)
        try container.encodeOptional(input.endDate, forKey: .endDate)
        try container.encodeOptional(input.startTime, forKey: .startTime)
        try container.encodeOptional(input.endTime, forKey: .endTime)
        try container.encodeOptional(input.estimatedDriveMinutes, forKey: .estimatedDriveMinutes)
        try container.encodeOptional(input.notes, forKey: .notes)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeOptional<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}

private struct TripsHomeParameters: Encodable {
    let homeID: UUID

    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
    }
}

private struct PlanTripAgainParameters: Encodable {
    let tripID: UUID
    let startDate: String
    let endDate: String
    let startTime: String?
    let endTime: String?

    enum CodingKeys: String, CodingKey {
        case tripID = "requested_trip_id"
        case startDate = "requested_start_date"
        case endDate = "requested_end_date"
        case startTime = "requested_start_time"
        case endTime = "requested_end_time"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tripID, forKey: .tripID)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encodeOptional(startTime, forKey: .startTime)
        try container.encodeOptional(endTime, forKey: .endTime)
    }
}

private struct CompleteTripParameters: Encodable {
    let tripID: UUID

    enum CodingKeys: String, CodingKey {
        case tripID = "requested_trip_id"
    }
}

private struct DeleteTripParameters: Encodable {
    let tripID: UUID

    enum CodingKeys: String, CodingKey {
        case tripID = "requested_trip_id"
    }
}
