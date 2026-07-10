import Foundation

enum IdeaCategory: String, CaseIterable, Codable, Identifiable {
    case restaurant = "Restaurant"
    case cafe = "Cafe"
    case hawker = "Hawker"
    case bar = "Bar"
    case dessertShop = "Dessert Shop"
    case activity = "Activity"
    case event = "Event"
    case shop = "Shop"
    case photobooth = "Photobooth"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .restaurant: "fork.knife"
        case .cafe: "cup.and.saucer"
        case .hawker: "takeoutbag.and.cup.and.straw"
        case .bar: "wineglass"
        case .dessertShop: "birthday.cake"
        case .activity: "figure.play"
        case .event: "calendar"
        case .shop: "bag"
        case .photobooth: "camera"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = Self.matching(value) ?? .restaurant
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static func matching(_ value: String) -> IdeaCategory? {
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]"#, with: "", options: .regularExpression)

        switch normalized {
        case "restaurant": return .restaurant
        case "cafe", "caf": return .cafe
        case "hawker", "hawkercentre", "hawkercenter": return .hawker
        case "bar": return .bar
        case "dessert", "dessertshop": return .dessertShop
        case "activity": return .activity
        case "event": return .event
        case "shop", "store": return .shop
        case "photobooth", "photostudio": return .photobooth
        default:
            return allCases.first { $0.rawValue.localizedCaseInsensitiveCompare(value) == .orderedSame }
        }
    }
}

enum IdeaTag: String, CaseIterable, Codable, Identifiable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case dessert = "Dessert"
    case budget = "Budget"
    case fancy = "Fancy"
    case halal = "Halal"
    case deal = "Deal"
    case hiddenGem = "Hidden Gem"
    case indoor = "Indoor"
    case rainyDay = "Rainy Day"

    var id: String { rawValue }
}

enum CuisineTag: String, CaseIterable, Codable, Identifiable {
    case japanese = "Japanese"
    case italian = "Italian"
    case chinese = "Chinese"
    case korean = "Korean"
    case thai = "Thai"
    case western = "Western"
    case indian = "Indian"
    case malay = "Malay"
    case indonesian = "Indonesian"
    case vietnamese = "Vietnamese"
    case mediterranean = "Mediterranean"
    case mexican = "Mexican"
    case french = "French"
    case local = "Local"
    case fusion = "Fusion"
    case dessert = "Dessert"

    var id: String { rawValue }
}

enum FoodTag: String, CaseIterable, Codable, Identifiable {
    case steak = "Steak"
    case sushi = "Sushi"
    case ramen = "Ramen"
    case gyukatsu = "Gyukatsu"
    case omakase = "Omakase"
    case sashimi = "Sashimi"
    case iceCream = "Ice Cream"
    case friedChicken = "Fried Chicken"
    case sandwiches = "Sandwiches"
    case pasta = "Pasta"
    case pizza = "Pizza"
    case burgers = "Burgers"
    case coffee = "Coffee"
    case matcha = "Matcha"
    case pastries = "Pastries"
    case oysters = "Oysters"
    case beef = "Beef"
    case noodles = "Noodles"
    case rice = "Rice"
    case desserts = "Desserts"
    case waffles = "Waffles"
    case gelato = "Gelato"
    case seafood = "Seafood"
    case hotpot = "Hotpot"
    case dimSum = "Dim Sum"
    case somen = "Somen"
    case monaka = "Monaka"

    var id: String { rawValue }
}

struct PlaceLocation: Codable, Hashable {
    var name: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    var websiteURL: URL?
    var phoneNumber: String?
    var openingHoursSummary: String?
}

enum DealStatus: String, Codable {
    case active
    case expired
    case needsConfirmation
    case unknown

    var label: String {
        switch self {
        case .active: return "Active"
        case .expired: return "Expired"
        case .needsConfirmation: return "Confirm"
        case .unknown: return "Unknown"
        }
    }
}

struct Deal: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var details: String
    var startsAt: Date?
    var endsAt: Date?
    var status: DealStatus

    init(
        id: UUID = UUID(),
        title: String,
        details: String,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        status: DealStatus = .unknown
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.status = status
    }

    var isVisible: Bool {
        !isExpired
    }

    var isExpired: Bool {
        if status == .expired { return true }
        guard let endsAt else { return false }
        return Calendar.current.startOfDay(for: endsAt) < Calendar.current.startOfDay(for: .now)
    }

    var isEndingSoon: Bool {
        guard !isExpired, let days = daysUntilEnd else { return false }
        return (0...7).contains(days)
    }

    var daysUntilEnd: Int? {
        guard let endsAt else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let endDay = calendar.startOfDay(for: endsAt)
        return calendar.dateComponents([.day], from: today, to: endDay).day
    }

    var countdownText: String? {
        if isExpired { return "Expired" }
        guard let daysUntilEnd else {
            return status == .needsConfirmation ? "Confirm deal" : nil
        }

        if daysUntilEnd == 0 { return "Ends today" }
        if daysUntilEnd == 1 { return "Ends tomorrow" }
        if daysUntilEnd > 1 { return "Ends in \(daysUntilEnd) days" }
        return "Expired"
    }
}

struct SourcePost: Identifiable, Codable, Hashable {
    var id: UUID
    var url: URL
    var platform: String
    var caption: String
    var importedAt: Date
    var postedAt: Date?

    init(id: UUID = UUID(), url: URL, platform: String, caption: String, importedAt: Date = .now, postedAt: Date? = nil) {
        self.id = id
        self.url = url
        self.platform = platform
        self.caption = caption
        self.importedAt = importedAt
        self.postedAt = postedAt
    }
}

struct Visit: Identifiable, Codable, Hashable {
    var id: UUID
    // Optionals so visits saved before these fields existed still decode.
    var title: String?
    var visitedAt: Date
    var amountSpent: Decimal?
    var notes: String
    var photoNames: [String]
    var review: Review
    var addedByUserID: String?
    var addedByDisplayName: String?
    var addedByPhotoURL: URL?

    init(
        id: UUID = UUID(),
        title: String? = nil,
        visitedAt: Date = .now,
        amountSpent: Decimal? = nil,
        notes: String = "",
        photoNames: [String] = [],
        review: Review = Review(),
        addedByUserID: String? = nil,
        addedByDisplayName: String? = nil,
        addedByPhotoURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.visitedAt = visitedAt
        self.amountSpent = amountSpent
        self.notes = notes
        self.photoNames = photoNames
        self.review = review
        self.addedByUserID = addedByUserID
        self.addedByDisplayName = addedByDisplayName
        self.addedByPhotoURL = addedByPhotoURL
    }

    // Photos are device-local files; on a partner's device the names exist
    // but the files do not.
    var localPhotoNames: [String] {
        photoNames.filter { name in
            guard let url = DateIdeaImageStore.fileURL(for: name) else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }
    }
}

struct Review: Codable, Hashable {
    var food: Int
    var ambience: Int
    var value: Int
    var service: Int
    var revisitPotential: Int

    init(food: Int = 3, ambience: Int = 3, value: Int = 3, service: Int = 3, revisitPotential: Int = 3) {
        self.food = food
        self.ambience = ambience
        self.value = value
        self.service = service
        self.revisitPotential = revisitPotential
    }

    var overallScore: Double {
        let total = food + ambience + value + service + revisitPotential
        return Double(total) / 5.0
    }

    func score(for metric: ReviewMetric) -> Double {
        switch metric {
        case .overall:
            return overallScore
        case .food:
            return Double(food)
        case .ambience:
            return Double(ambience)
        case .value:
            return Double(value)
        case .service:
            return Double(service)
        case .revisitPotential:
            return Double(revisitPotential)
        }
    }
}

enum ReviewMetric: String, CaseIterable, Identifiable {
    case overall = "Overall"
    case food = "Food"
    case ambience = "Ambience"
    case value = "Value"
    case service = "Service"
    case revisitPotential = "Revisit"

    var id: String { rawValue }
}

// Cleans free-form tag strings coming from Apple Intelligence, the fallback
// parser, or user input: trims junk, applies aliases, and dedupes.
enum PlaceTagNormalizer {
    private static let aliases: [String: String] = [
        "ramyeon": "Ramyun",
        "korean ramen": "Ramyun",
        "1 for 1": "1-for-1"
    ]

    private static let rejectedWords: Set<String> = [
        "food", "foodie", "delicious", "yummy", "tasty", "singapore", "sg",
        "must try", "viral", "instagram", "tiktok", "fyp", "date idea", "hidden gem"
    ]

    static func normalize(_ rawTags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for raw in rawTags {
            guard let tag = normalizeSingle(raw) else { continue }
            let key = tag.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(tag)
        }

        return result
    }

    static func normalizeSingle(_ raw: String) -> String? {
        var value = raw
            .replacingOccurrences(of: "#", with: " ")
            .replacingOccurrences(of: "@", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !value.isEmpty, value.count <= 28 else { return nil }

        let lower = value.lowercased()
        if let alias = aliases[lower] {
            return alias
        }
        guard !rejectedWords.contains(lower) else { return nil }

        // Title-case fully lowercase tags; keep deliberate casing as typed.
        if value == lower {
            value = value
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }

        return value
    }
}

struct DateIdea: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var category: IdeaCategory
    var tags: [IdeaTag]
    // Free-form tag strings (AI-suggested + user-edited). The old CuisineTag/
    // FoodTag enums remain only as a decode/encode bridge for existing data.
    var cuisineTagNames: [String]
    var foodTagNames: [String]
    var location: PlaceLocation
    var factualSummary: String
    var notes: String
    var imageName: String?
    var imageURL: URL?
    var deals: [Deal]
    var sourcePosts: [SourcePost]
    var visits: [Visit]
    var createdByUserID: String?
    var createdByDisplayName: String?
    var createdByPhotoURL: URL?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        category: IdeaCategory,
        tags: [IdeaTag] = [],
        cuisineTagNames: [String] = [],
        foodTagNames: [String] = [],
        location: PlaceLocation,
        factualSummary: String,
        notes: String = "",
        imageName: String? = nil,
        imageURL: URL? = nil,
        deals: [Deal] = [],
        sourcePosts: [SourcePost] = [],
        visits: [Visit] = [],
        createdByUserID: String? = nil,
        createdByDisplayName: String? = nil,
        createdByPhotoURL: URL? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.tags = tags
        self.cuisineTagNames = PlaceTagNormalizer.normalize(cuisineTagNames)
        self.foodTagNames = PlaceTagNormalizer.normalize(foodTagNames)
        self.location = location
        self.factualSummary = factualSummary
        self.notes = notes
        self.imageName = imageName
        self.imageURL = imageURL
        self.deals = deals
        self.sourcePosts = sourcePosts
        self.visits = visits
        self.createdByUserID = createdByUserID
        self.createdByDisplayName = createdByDisplayName
        self.createdByPhotoURL = createdByPhotoURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case category
        case tags
        case cuisineTags
        case foodTags
        case cuisineTagNames
        case foodTagNames
        case location
        case factualSummary
        case notes
        case imageName
        case imageURL
        case deals
        case sourcePosts
        case visits
        case createdByUserID
        case createdByDisplayName
        case createdByPhotoURL
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decode(IdeaCategory.self, forKey: .category)
        tags = try container.decodeIfPresent([IdeaTag].self, forKey: .tags) ?? []

        // Old data stored enum raw values under cuisineTags/foodTags — those
        // raw values are display strings, so merge them into the new arrays.
        let legacyCuisine = (try? container.decodeIfPresent([String].self, forKey: .cuisineTags)) ?? []
        let legacyFood = (try? container.decodeIfPresent([String].self, forKey: .foodTags)) ?? []
        let newCuisine = try container.decodeIfPresent([String].self, forKey: .cuisineTagNames) ?? []
        let newFood = try container.decodeIfPresent([String].self, forKey: .foodTagNames) ?? []
        var mergedCuisine = PlaceTagNormalizer.normalize(newCuisine + legacyCuisine)
        var mergedFood = PlaceTagNormalizer.normalize(newFood + legacyFood)

        if mergedCuisine.isEmpty, category == .dessertShop || tags.contains(.dessert) {
            mergedCuisine = [CuisineTag.dessert.rawValue]
        }
        if mergedFood.isEmpty, category == .dessertShop || tags.contains(.dessert) {
            mergedFood = [FoodTag.desserts.rawValue]
        }

        cuisineTagNames = mergedCuisine
        foodTagNames = mergedFood
        location = try container.decode(PlaceLocation.self, forKey: .location)
        factualSummary = try container.decode(String.self, forKey: .factualSummary)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        imageName = try container.decodeIfPresent(String.self, forKey: .imageName)
        imageURL = try container.decodeIfPresent(URL.self, forKey: .imageURL)
        deals = try container.decodeIfPresent([Deal].self, forKey: .deals) ?? []
        sourcePosts = try container.decodeIfPresent([SourcePost].self, forKey: .sourcePosts) ?? []
        visits = try container.decodeIfPresent([Visit].self, forKey: .visits) ?? []
        createdByUserID = try container.decodeIfPresent(String.self, forKey: .createdByUserID)
        createdByDisplayName = try container.decodeIfPresent(String.self, forKey: .createdByDisplayName)
        createdByPhotoURL = try container.decodeIfPresent(URL.self, forKey: .createdByPhotoURL)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(category, forKey: .category)
        try container.encode(tags, forKey: .tags)
        try container.encode(cuisineTagNames, forKey: .cuisineTagNames)
        try container.encode(foodTagNames, forKey: .foodTagNames)
        // Also write enum-compatible values under the legacy keys so app
        // versions before the flexible-tag change can still decode this place.
        try container.encode(cuisineTagNames.compactMap { CuisineTag(rawValue: $0) }, forKey: .cuisineTags)
        try container.encode(foodTagNames.compactMap { FoodTag(rawValue: $0) }, forKey: .foodTags)
        try container.encode(location, forKey: .location)
        try container.encode(factualSummary, forKey: .factualSummary)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(imageName, forKey: .imageName)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
        try container.encode(deals, forKey: .deals)
        try container.encode(sourcePosts, forKey: .sourcePosts)
        try container.encode(visits, forKey: .visits)
        try container.encodeIfPresent(createdByUserID, forKey: .createdByUserID)
        try container.encodeIfPresent(createdByDisplayName, forKey: .createdByDisplayName)
        try container.encodeIfPresent(createdByPhotoURL, forKey: .createdByPhotoURL)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    var hasVisited: Bool {
        !visits.isEmpty
    }

    var activeDeals: [Deal] {
        deals.filter(\.isVisible)
    }

    var endingSoonDeals: [Deal] {
        activeDeals.filter(\.isEndingSoon)
    }

    var nextDealCountdownText: String? {
        activeDeals
            .compactMap { deal -> (Int, String)? in
                guard let days = deal.daysUntilEnd, let text = deal.countdownText else { return nil }
                return (days, text)
            }
            .sorted { $0.0 < $1.0 }
            .first?
            .1
    }

    var displayTagTitles: [String] {
        (cuisineTagNames + foodTagNames).uniqueCaseInsensitive()
    }

    var latestReview: Review? {
        visits.sorted { $0.visitedAt > $1.visitedAt }.first?.review
    }

    var duplicateKey: String {
        "\(title)|\(location.address)"
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
    }

}

private extension Array where Element == String {
    func uniqueCaseInsensitive() -> [String] {
        reduce(into: [String]()) { result, value in
            let normalized = value.lowercased()
            guard !result.contains(where: { $0.lowercased() == normalized }) else { return }
            result.append(value)
        }
    }
}

enum DateIdeaImageStore {
    static func save(data: Data) -> String? {
        guard let directoryURL else { return nil }

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let fileName = "\(UUID().uuidString).jpg"
            try data.write(to: directoryURL.appendingPathComponent(fileName), options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    static func fileURL(for imageName: String?) -> URL? {
        guard let imageName, let directoryURL else { return nil }
        return directoryURL.appendingPathComponent(imageName)
    }

    private static var directoryURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("DateIdeaImages", isDirectory: true)
    }
}
