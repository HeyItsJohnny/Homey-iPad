import Foundation

struct TripItineraryItem: Decodable, Identifiable, Equatable, Sendable {
    var id: UUID
    var tripID: UUID
    var itemDate: Date
    var startTime: String?
    var endTime: String?
    var title: String
    var locationName: String?
    var locationAddress: String?
    var notes: String?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id = "itinerary_item_id"
        case tripID = "trip_id"
        case itemDate = "item_date"
        case startTime = "start_time"
        case endTime = "end_time"
        case title
        case locationName = "location_name"
        case locationAddress = "location_address"
        case notes
        case sortOrder = "sort_order"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        tripID = try container.decode(UUID.self, forKey: .tripID)
        let dateText = try container.decode(String.self, forKey: .itemDate)
        guard let decodedDate = TripDateFormatters.backendDate.date(from: dateText) else {
            throw DecodingError.dataCorruptedError(
                forKey: .itemDate,
                in: container,
                debugDescription: "Invalid itinerary item date: \(dateText)"
            )
        }
        itemDate = decodedDate
        startTime = try container.decodeIfPresent(String.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(String.self, forKey: .endTime)
        title = try container.decode(String.self, forKey: .title)
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        locationAddress = try container.decodeIfPresent(String.self, forKey: .locationAddress)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
    }
}

struct TripItineraryDraft: Sendable {
    var title = ""
    var itemDate: Date
    var includesStartTime = false
    var includesEndTime = false
    var startTime = TripTimeFormatters.defaultStartDate
    var endTime = TripTimeFormatters.defaultEndDate
    var locationName = ""
    var locationAddress = ""
    var notes = ""

    init(itemDate: Date) {
        self.itemDate = TripDateFormatters.localDate(itemDate)
    }

    @MainActor init(item: TripItineraryItem) {
        title = item.title
        itemDate = TripDateFormatters.localDate(item.itemDate)
        includesStartTime = item.startTime != nil
        includesEndTime = item.endTime != nil
        startTime = TripTimeFormatters.date(from: item.startTime) ?? TripTimeFormatters.defaultStartDate
        endTime = TripTimeFormatters.date(from: item.endTime) ?? TripTimeFormatters.defaultEndDate
        locationName = item.locationName ?? ""
        locationAddress = item.locationAddress ?? ""
        notes = item.notes ?? ""
    }
}

struct TripItineraryDay: Identifiable, Equatable, Sendable {
    let index: Int
    let date: Date
    let items: [TripItineraryItem]

    var id: String { TripDateFormatters.backendDate.string(from: date) }
}

enum TripItineraryDateFormatters {
    static let dayHeader: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }()
}
