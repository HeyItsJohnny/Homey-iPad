import Foundation

enum TripStatus: String, Codable, CaseIterable, Sendable {
    case idea
    case planned
    case active
    case completed
    case cancelled
}

enum TripDurationType: String, Codable, CaseIterable, Sendable {
    case fewHours = "few_hours"
    case dayTrip = "day_trip"
    case weekend
    case multiDay = "multi_day"
    case custom

    var displayName: String {
        switch self {
        case .fewHours: "Few Hours"
        case .dayTrip: "Day Trip"
        case .weekend: "Weekend"
        case .multiDay: "Multi-Day"
        case .custom: "Custom"
        }
    }
}

enum TripEditorMode: Sendable {
    case saveIdea
    case planTrip
    case edit(TripStatus)

    var title: String {
        switch self {
        case .saveIdea: "Save Trip Idea"
        case .planTrip: "Plan a Trip"
        case .edit: "Edit Trip"
        }
    }

    var status: TripStatus {
        switch self {
        case .saveIdea: .idea
        case .planTrip: .planned
        case let .edit(status): status
        }
    }

    var showsSchedule: Bool {
        switch self {
        case .saveIdea: false
        case .planTrip: true
        case let .edit(status): status != .idea
        }
    }
}

struct TripEditorDraft: Sendable {
    var title = ""
    var destinationName = ""
    var destinationAddress = ""
    var durationType: TripDurationType = .dayTrip
    var startDate = TripDateFormatters.localNoon(Date())
    var endDate = TripDateFormatters.localNoon(Date())
    var includesTimes = false
    var startTime = TripTimeFormatters.defaultStartDate
    var endTime = TripTimeFormatters.defaultEndDate
    var estimatedDriveHours = 0
    var estimatedDriveMinutes = 0
    var notes = ""

    init() {}

    @MainActor init(trip: Trip) {
        title = trip.title
        destinationName = trip.destinationName ?? ""
        destinationAddress = trip.destinationAddress ?? ""
        durationType = trip.durationType
        startDate = trip.startDate.map(TripDateFormatters.localDate) ?? TripDateFormatters.localNoon(Date())
        endDate = trip.endDate.map(TripDateFormatters.localDate) ?? startDate
        includesTimes = trip.startTime != nil || trip.endTime != nil
        startTime = TripTimeFormatters.date(from: trip.startTime) ?? TripTimeFormatters.defaultStartDate
        endTime = TripTimeFormatters.date(from: trip.endTime) ?? TripTimeFormatters.defaultEndDate
        estimatedDriveHours = (trip.estimatedDriveMinutes ?? 0) / 60
        estimatedDriveMinutes = (trip.estimatedDriveMinutes ?? 0) % 60
        notes = trip.notes ?? ""
    }
}

struct Trip: Decodable, Identifiable, Equatable, Sendable {
    let id: UUID
    let organizerHomeID: UUID
    let title: String
    let destinationName: String?
    let destinationAddress: String?
    let status: TripStatus
    let durationType: TripDurationType
    let startDate: Date?
    let endDate: Date?
    let startTime: String?
    let endTime: String?
    let estimatedDriveMinutes: Int?
    let notes: String?
    let rating: Int?
    let wouldDoAgain: Bool?
    let sourceType: String?
    let sourceURL: String?
    let sourceTitle: String?
    let sourceText: String?
    let sourceImageURL: String?
    let clonedFromTripID: UUID?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id = "trip_id"
        case organizerHomeID = "organizer_home_id"
        case title
        case destinationName = "destination_name"
        case destinationAddress = "destination_address"
        case status
        case durationType = "duration_type"
        case startDate = "start_date"
        case endDate = "end_date"
        case startTime = "start_time"
        case endTime = "end_time"
        case estimatedDriveMinutes = "estimated_drive_minutes"
        case notes
        case rating
        case wouldDoAgain = "would_do_again"
        case sourceType = "source_type"
        case sourceURL = "source_url"
        case sourceTitle = "source_title"
        case sourceText = "source_text"
        case sourceImageURL = "source_image_url"
        case clonedFromTripID = "cloned_from_trip_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        organizerHomeID = try container.decode(UUID.self, forKey: .organizerHomeID)
        title = try container.decode(String.self, forKey: .title)
        destinationName = try container.decodeIfPresent(String.self, forKey: .destinationName)
        destinationAddress = try container.decodeIfPresent(String.self, forKey: .destinationAddress)
        status = try container.decode(TripStatus.self, forKey: .status)
        durationType = try container.decode(TripDurationType.self, forKey: .durationType)
        startDate = try Self.decodeLocalDate(from: container, forKey: .startDate)
        endDate = try Self.decodeLocalDate(from: container, forKey: .endDate)
        startTime = try container.decodeIfPresent(String.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(String.self, forKey: .endTime)
        estimatedDriveMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedDriveMinutes)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        rating = try container.decodeIfPresent(Int.self, forKey: .rating)
        wouldDoAgain = try container.decodeIfPresent(Bool.self, forKey: .wouldDoAgain)
        sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        sourceTitle = try container.decodeIfPresent(String.self, forKey: .sourceTitle)
        sourceText = try container.decodeIfPresent(String.self, forKey: .sourceText)
        sourceImageURL = try container.decodeIfPresent(String.self, forKey: .sourceImageURL)
        clonedFromTripID = try container.decodeIfPresent(UUID.self, forKey: .clonedFromTripID)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
    }

    private static func decodeLocalDate(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Date? {
        guard let value = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
        return TripDateFormatters.backendDate.date(from: value)
    }
}

enum TripsSection: String, CaseIterable, Identifiable {
    case saved = "Saved"
    case planned = "Planned"
    case past = "Past"

    var id: String { rawValue }
}

enum TripDateFormatters {
    static let backendDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let cardDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static func backendString(from localDate: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: localDate)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func localDate(_ backendDate: Date) -> Date {
        let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: backendDate)
        return Calendar.current.date(from: DateComponents(
            year: components.year,
            month: components.month,
            day: components.day,
            hour: 12
        )) ?? backendDate
    }

    static func localNoon(_ date: Date) -> Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }

    static func range(start: Date?, end: Date?) -> String? {
        guard let start else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let end, !calendar.isDate(start, inSameDayAs: end) else {
            return cardDate.string(from: start)
        }
        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: end)
        let startMonth = calendar.component(.month, from: start)
        let endMonth = calendar.component(.month, from: end)
        if startYear == endYear, startMonth == endMonth {
            return "\(cardDate.string(from: start))–\(calendar.component(.day, from: end))"
        }
        return "\(cardDate.string(from: start)) – \(cardDate.string(from: end))"
    }
}

enum TripTimeFormatters {
    static let defaultStartDate = date(hour: 9)
    static let defaultEndDate = date(hour: 17)

    static func date(from backendTime: String?) -> Date? {
        guard let backendTime else { return nil }
        let pieces = backendTime.split(separator: ":").compactMap { Int($0.prefix(2)) }
        guard pieces.count >= 2 else { return nil }
        return date(hour: pieces[0], minute: pieces[1])
    }

    static func backendString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d:00", components.hour ?? 0, components.minute ?? 0)
    }

    static func displayString(_ backendTime: String?) -> String? {
        guard let date = date(from: backendTime) else { return nil }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private static func date(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: hour, minute: minute)) ?? Date()
    }
}
