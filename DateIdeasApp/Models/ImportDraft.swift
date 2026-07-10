import Foundation

enum ExtractionMethod: String, Codable, Hashable {
    case appleIntelligence = "Apple Intelligence"
    case parser = "Parser"

    var systemImage: String {
        switch self {
        case .appleIntelligence:
            return "sparkles"
        case .parser:
            return "slider.horizontal.3"
        }
    }
}

enum ImportStage: Equatable {
    case fetchingCaption
    case extracting(ExtractionMethod)
    case resolvingPlace
}

// Fields streamed live from Apple Intelligence while extraction runs.
struct ExtractionPreview: Equatable {
    var name: String?
    var address: String?
    var summary: String?

    var isEmpty: Bool {
        name == nil && address == nil && summary == nil
    }
}

struct ImportDraft: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceURL: URL
    var platform: String
    var rawCaption: String
    var extractedIdea: DateIdea
    var confidence: Double
    var extractionMethod: ExtractionMethod
    var extractionNote: String?
    var needsManualReview: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case sourceURL
        case platform
        case rawCaption
        case extractedIdea
        case confidence
        case extractionMethod
        case extractionNote
        case needsManualReview
    }

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        platform: String,
        rawCaption: String,
        extractedIdea: DateIdea,
        confidence: Double = 0.65,
        extractionMethod: ExtractionMethod = .parser,
        extractionNote: String? = nil,
        needsManualReview: Bool = true
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.platform = platform
        self.rawCaption = rawCaption
        self.extractedIdea = extractedIdea
        self.confidence = confidence
        self.extractionMethod = extractionMethod
        self.extractionNote = extractionNote
        self.needsManualReview = needsManualReview
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        sourceURL = try container.decode(URL.self, forKey: .sourceURL)
        platform = try container.decode(String.self, forKey: .platform)
        rawCaption = try container.decode(String.self, forKey: .rawCaption)
        extractedIdea = try container.decode(DateIdea.self, forKey: .extractedIdea)
        confidence = try container.decode(Double.self, forKey: .confidence)
        extractionMethod = try container.decodeIfPresent(ExtractionMethod.self, forKey: .extractionMethod) ?? .parser
        extractionNote = try container.decodeIfPresent(String.self, forKey: .extractionNote)
        needsManualReview = try container.decode(Bool.self, forKey: .needsManualReview)
    }
}
