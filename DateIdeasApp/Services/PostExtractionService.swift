import Foundation
import FoundationModels
import LinkPresentation
import MapKit
import UniformTypeIdentifiers
import UIKit

protocol PostExtractionServicing {
    func extract(
        from url: URL,
        supplementalText: String,
        onStage: @escaping @MainActor (ImportStage) -> Void,
        onPartial: @escaping @MainActor (ExtractionPreview) -> Void
    ) async -> ImportDraft
}

extension PostExtractionServicing {
    func extract(from url: URL) async -> ImportDraft {
        await extract(from: url, supplementalText: "", onStage: { _ in }, onPartial: { _ in })
    }

    func extract(from url: URL, supplementalText: String) async -> ImportDraft {
        await extract(from: url, supplementalText: supplementalText, onStage: { _ in }, onPartial: { _ in })
    }
}

// Prepares the on-device model ahead of a likely import so the first
// request doesn't pay the model-load latency.
@MainActor
enum CaptionExtractorPrewarmer {
    static func prewarm() {
        FoundationModelCaptionExtractor.prewarm()
    }
}

struct MockPostExtractionService: PostExtractionServicing {
    func extract(
        from url: URL,
        supplementalText: String,
        onStage: @escaping @MainActor (ImportStage) -> Void,
        onPartial: @escaping @MainActor (ExtractionPreview) -> Void
    ) async -> ImportDraft {
        let platform: String
        if url.host?.contains("tiktok") == true {
            platform = "TikTok"
        } else if url.host?.contains("instagram") == true {
            platform = "Instagram"
        } else {
            platform = "Link"
        }

        await onStage(.fetchingCaption)
        let fetchedMetadata = supplementalText.isEmpty
            ? await LinkCaptionFetcher.metadata(from: url, platform: platform)
            : nil
        let extractionText = supplementalText.isEmpty ? (fetchedMetadata?.captionText ?? "") : supplementalText
        let fallbackParsed = CaptionIdeaParser.parse(extractionText)

        let hasCaption = !extractionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let plannedMethod: ExtractionMethod = hasCaption && SystemLanguageModel.default.isAvailable ? .appleIntelligence : .parser
        await onStage(.extracting(plannedMethod))
        let aiOutcome = await FoundationModelCaptionExtractor.extract(from: extractionText, onPartial: onPartial)
        let aiResult = aiOutcome.result
        let parsed = aiResult?.parsedCaption ?? fallbackParsed
        let caption = extractionText.isEmpty
            ? "Imported from \(platform), but no public caption metadata was available from the link."
            : extractionText
        let extractionMethod: ExtractionMethod = aiResult == nil ? .parser : .appleIntelligence
        let extractionNote = aiResult?.note ?? "Apple Intelligence was not used. \(aiOutcome.note)"

        await onStage(.resolvingPlace)
        let resolvedPlace = await AppleMapsPlaceResolver.resolve(name: parsed.title, address: parsed.address)
        let localImageName = fetchedMetadata?.thumbnailURL == nil
            ? await LinkPreviewImageResolver.imageName(from: url)
            : nil
        let deals = DealFreshnessPolicy.applied(to: parsed.deals, postedAt: fetchedMetadata?.postedAt)

        let source = SourcePost(url: url, platform: platform, caption: caption, postedAt: fetchedMetadata?.postedAt)
        let idea = DateIdea(
            title: parsed.title,
            category: parsed.category,
            cuisineTagNames: parsed.cuisineTags,
            foodTagNames: parsed.foodTags,
            location: PlaceLocation(
                name: parsed.title,
                address: parsed.address,
                latitude: resolvedPlace?.latitude,
                longitude: resolvedPlace?.longitude,
                websiteURL: resolvedPlace?.websiteURL,
                phoneNumber: resolvedPlace?.phoneNumber,
                openingHoursSummary: nil
            ),
            factualSummary: parsed.summary,
            notes: parsed.notes,
            imageName: localImageName,
            imageURL: fetchedMetadata?.thumbnailURL,
            deals: deals,
            sourcePosts: [source]
        )

        return ImportDraft(
            sourceURL: url,
            platform: platform,
            rawCaption: caption,
            extractedIdea: idea,
            confidence: parsed.confidence,
            extractionMethod: extractionMethod,
            extractionNote: extractionNote,
            needsManualReview: true
        )
    }
}

private struct LinkPostMetadata {
    var captionText: String?
    var thumbnailURL: URL?
    var postedAt: Date?
}

private enum LinkCaptionFetcher {
    static func metadata(from url: URL, platform: String) async -> LinkPostMetadata? {
        if platform == "TikTok" {
            return await tiktokOEmbedMetadata(from: url)
        }

        return await publicPageMetadata(from: url)
    }

    private static func tiktokOEmbedMetadata(from url: URL) async -> LinkPostMetadata? {
        guard var components = URLComponents(string: "https://www.tiktok.com/oembed") else { return nil }
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        guard let requestURL = components.url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: requestURL)
            let response = try JSONDecoder().decode(TikTokOEmbedResponse.self, from: data)
            let captionText = response.title?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return LinkPostMetadata(captionText: captionText, thumbnailURL: response.thumbnailURL, postedAt: nil)
        } catch {
            return nil
        }
    }

    private static func publicPageMetadata(from url: URL) async -> LinkPostMetadata? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }

            let descriptionMetadata = [
                metaContent(named: "og:description", in: html),
                metaContent(named: "twitter:description", in: html),
                metaContent(named: "description", in: html)
            ]
            .compactMap { $0 }
            .map(cleanMetadataText)
            .filter { !$0.isEmpty && !$0.localizedCaseInsensitiveContains("log in") }

            let titleMetadata = [
                metaContent(named: "og:title", in: html),
                metaContent(named: "twitter:title", in: html)
            ]
            .compactMap { $0 }
            .map(cleanMetadataText)
            .filter { !$0.isEmpty && !$0.localizedCaseInsensitiveContains("log in") }

            let imageMetadata = [
                metaContent(named: "og:image", in: html),
                metaContent(named: "twitter:image", in: html),
                metaContent(named: "twitter:image:src", in: html)
            ]
            .compactMap { $0 }
            .compactMap { thumbnailURL(from: $0, relativeTo: url) }

            return LinkPostMetadata(
                captionText: bestCaption(from: descriptionMetadata) ?? bestCaption(from: titleMetadata),
                thumbnailURL: imageMetadata.first,
                postedAt: postedDate(from: descriptionMetadata + titleMetadata)
            )
        } catch {
            return nil
        }
    }

    private static func postedDate(from values: [String]) -> Date? {
        for value in values {
            guard let range = value.range(
                of: #"(?i)\bon\s+([A-Z][a-z]+\s+\d{1,2},\s+\d{4})"#,
                options: .regularExpression
            ) else { continue }

            let matched = String(value[range])
                .replacingOccurrences(of: #"(?i)^on\s+"#, with: "", options: .regularExpression)

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMMM d, yyyy"

            if let date = formatter.date(from: matched) {
                return date
            }
        }

        return nil
    }

    private static func thumbnailURL(from value: String, relativeTo baseURL: URL) -> URL? {
        let cleaned = decodeHTMLEntities(in: value)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return nil }
        return URL(string: cleaned, relativeTo: baseURL)?.absoluteURL
    }

    private static func metaContent(named name: String, in html: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            #"<meta[^>]+(?:property|name)=["']"# + escapedName + #"["'][^>]+content=["']([^"']+)["'][^>]*>"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["']"# + escapedName + #"["'][^>]*>"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            guard let match = regex.firstMatch(in: html, range: range),
                  match.numberOfRanges > 1,
                  let contentRange = Range(match.range(at: 1), in: html) else { continue }
            return String(html[contentRange])
        }

        return nil
    }

    private static func cleanMetadataText(_ value: String) -> String {
        normalizeCaptionWrapper(decodeHTMLEntities(in: value))
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\bInstagram reel\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\u{200E}", with: "")
            .replacingOccurrences(of: "\u{200F}", with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func bestCaption(from values: [String]) -> String? {
        let uniqueValues = values.reduce(into: [String]()) { result, value in
            let key = canonicalCaptionKey(value)
            guard !key.isEmpty, !result.contains(where: { canonicalCaptionKey($0) == key }) else { return }
            result.append(value)
        }

        return uniqueValues.max { lhs, rhs in
            captionScore(lhs) < captionScore(rhs)
        }
    }

    private static func captionScore(_ value: String) -> Int {
        var score = min(value.count, 2_000)

        if value.contains("@") { score += 250 }
        if value.contains("📍") { score += 250 }
        if value.localizedCaseInsensitiveContains(" on Instagram") { score -= 100 }
        if value.localizedCaseInsensitiveContains("likes,") { score -= 100 }

        return score
    }

    private static func canonicalCaptionKey(_ value: String) -> String {
        normalizeCaptionWrapper(value)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9@#$]+"#, with: "", options: .regularExpression)
    }

    private static func normalizeCaptionWrapper(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"^\d{1,3}(,\d{3})?\s+likes,\s+\d{1,3}(,\d{3})?\s+comments\s+-\s+[^:]{1,120}:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^[^:]{1,100}\s+on Instagram:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^Instagram reel\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    private static func decodeHTMLEntities(in value: String) -> String {
        var decoded = value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        guard let regex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) else { return decoded }

        for _ in 0..<3 {
            let nsValue = decoded as NSString
            let matches = regex.matches(in: decoded, range: NSRange(location: 0, length: nsValue.length)).reversed()
            guard !matches.isEmpty else { break }

            for match in matches {
                let entity = nsValue.substring(with: match.range(at: 1))
                let scalarValue: UInt32?

                if entity.lowercased().hasPrefix("x") {
                    scalarValue = UInt32(entity.dropFirst(), radix: 16)
                } else {
                    scalarValue = UInt32(entity, radix: 10)
                }

                guard let scalarValue, let scalar = UnicodeScalar(scalarValue) else { continue }
                decoded = (decoded as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
            }
        }

        return decoded
    }
}

private struct TikTokOEmbedResponse: Decodable {
    var title: String?
    var authorName: String?
    var thumbnailURL: URL?

    enum CodingKeys: String, CodingKey {
        case title
        case authorName = "author_name"
        case thumbnailURL = "thumbnail_url"
    }
}

private enum LinkPreviewImageResolver {
    static func imageName(from url: URL) async -> String? {
        guard let data = await imageData(from: url) else { return nil }
        return DateIdeaImageStore.save(data: data)
    }

    private static func imageData(from url: URL) async -> Data? {
        await withCheckedContinuation { continuation in
            let metadataProvider = LPMetadataProvider()
            metadataProvider.timeout = 8
            metadataProvider.startFetchingMetadata(for: url) { metadata, _ in
                let itemProvider = metadata?.imageProvider ?? metadata?.iconProvider
                guard let itemProvider else {
                    continuation.resume(returning: nil)
                    return
                }

                itemProvider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
                    continuation.resume(returning: data(from: item))
                }
            }
        }
    }

    private static func data(from item: NSSecureCoding?) -> Data? {
        if let data = item as? Data {
            return normalizedJPEGData(from: data) ?? data
        }

        if let image = item as? UIImage {
            return image.jpegData(compressionQuality: 0.82)
        }

        if let url = item as? URL,
           let data = try? Data(contentsOf: url) {
            return normalizedJPEGData(from: data) ?? data
        }

        return nil
    }

    private static func normalizedJPEGData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return image.jpegData(compressionQuality: 0.82)
    }
}

private enum DealFreshnessPolicy {
    static func applied(to deals: [Deal], postedAt: Date?) -> [Deal] {
        guard let postedAt else { return deals }

        return deals.map { deal in
            var nextDeal = deal
            guard nextDeal.endsAt == nil, nextDeal.status == .unknown else { return nextDeal }

            if Calendar.current.dateComponents([.day], from: postedAt, to: .now).day ?? 0 > 30 {
                nextDeal.status = .needsConfirmation
                nextDeal.details = nextDeal.details.isEmpty
                    ? "Imported from a post older than one month. Confirm that this deal is still available."
                    : "\(nextDeal.details)\nConfirm availability: the source post is older than one month."
            }

            return nextDeal
        }
    }
}

struct ResolvedPlace {
    var latitude: Double
    var longitude: Double
    var websiteURL: URL?
    var phoneNumber: String?
}

enum AppleMapsPlaceResolver {
    private static let singaporeRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 1.3521, longitude: 103.8198),
        span: MKCoordinateSpan(latitudeDelta: 0.7, longitudeDelta: 0.9)
    )

    static func resolve(name: String, address: String) async -> ResolvedPlace? {
        let query = searchQuery(name: name, address: address)
        guard let mapItem = await localSearch(query: query) else { return nil }
        let coordinate = mapItem.location.coordinate

        return ResolvedPlace(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            websiteURL: mapItem.url,
            phoneNumber: mapItem.phoneNumber
        )
    }

    private static func searchQuery(name: String, address: String) -> String {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanAddress.isEmpty || cleanAddress.localizedCaseInsensitiveCompare("Singapore") == .orderedSame {
            return "\(cleanName) Singapore"
        }

        if cleanAddress.localizedCaseInsensitiveContains("singapore") {
            return "\(cleanName), \(cleanAddress)"
        }

        return "\(cleanName), \(cleanAddress), Singapore"
    }

    private static func localSearch(query: String) async -> MKMapItem? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = singaporeRegion

        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.first
        } catch {
            return nil
        }
    }
}

private struct ParsedCaption {
    var title: String
    var category: IdeaCategory
    var cuisineTags: [String]
    var foodTags: [String]
    var address: String
    var summary: String
    var notes: String
    var deals: [Deal]
    var confidence: Double
}

@Generable
private struct AIExtractedCaption {
    @Guide(description: "The exact public name of the restaurant, cafe, shop, event, activity, or date idea. Prefer the name found in a location/address line over the Instagram handle.")
    var name: String

    @Guide(description: "One establishment type: Restaurant, Cafe, Hawker, Bar, Dessert Shop, Activity, Event, Shop, or Photobooth.")
    var category: String

    @Guide(description: "The location or address. If a location line starts with the place name, exclude the place name from the address.")
    var address: String

    @Guide(description: "A short factual summary of what this place is and what it serves or offers.")
    var summary: String

    @Guide(description: "Broad cuisine or style tags supported by the caption, as short title-case words (e.g. Japanese, Korean, Fusion, Dessert). Empty when the caption gives no cuisine evidence. Never use hashtags, influencer or account names, mall names, addresses, or generic words like food or delicious.")
    var cuisineTags: [String]

    @Guide(description: "Specific dishes, drinks, or food items the caption mentions, as short title-case tags (e.g. Ramyun, Cocktails, Truffle Pasta, Matcha Latte). Empty when none are mentioned. Never use hashtags, influencer or account names, mall names, addresses, or generic words like food or delicious.")
    var foodTags: [String]

    @Guide(description: "Short deal or price details only when the caption clearly states a concrete promo, discount, or special price. Return an empty list when there is no clear deal.")
    var dealDetails: [String]

    @Guide(description: "Confidence from 0.0 to 1.0 based only on the caption evidence.")
    var confidence: Double
}

private enum FoundationModelCaptionExtractor {
    struct Result {
        var parsedCaption: ParsedCaption
        var note: String
    }

    struct Outcome {
        var result: Result?
        var note: String

        static func success(_ result: Result) -> Outcome {
            Outcome(result: result, note: result.note)
        }

        static func fallback(_ note: String) -> Outcome {
            Outcome(result: nil, note: note)
        }
    }

    @MainActor private static var prewarmedSession: LanguageModelSession?

    // Loads the model ahead of time; the next extract() consumes this session.
    @MainActor
    static func prewarm() {
        let model = SystemLanguageModel.default
        guard model.isAvailable, prewarmedSession == nil else { return }

        let session = makeSession(model: model)
        session.prewarm()
        prewarmedSession = session
    }

    @MainActor
    private static func takeSession(model: SystemLanguageModel) -> LanguageModelSession {
        defer { prewarmedSession = nil }
        return prewarmedSession ?? makeSession(model: model)
    }

    private static func makeSession(model: SystemLanguageModel) -> LanguageModelSession {
        LanguageModelSession(
            model: model,
            instructions: """
            Extract date idea information from social media captions for a private couple's saved-ideas app.
            Be conservative and factual. Do not invent opening hours, addresses, deals, cuisine, or names.
            Prefer a concrete place name from a pin/location line over an Instagram handle.
            If the pin says "Jypsy Parkland Green, East Coast Park, Singapore" and the handle is @jypsysg, the place name is "Jypsy" and the address is "Parkland Green, East Coast Park, Singapore".
            If the pin says "Sushi Zushi, Bugis Junction, B1-K21/22, Singapore", the place name is "Sushi Zushi" and the address is "Bugis Junction, B1-K21/22, Singapore".
            Use the category as the establishment type. Use cuisineTags for broad cuisines and foodTags for specific dishes or popular food items.
            Return no deals unless the caption clearly contains a concrete price, promo, discount, 1-for-1, loyalty offer, or promo code.
            """
        )
    }

    static func extract(
        from text: String,
        onPartial: @escaping @MainActor (ExtractionPreview) -> Void = { _ in }
    ) async -> Outcome {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return .fallback("No caption text was available to analyze.")
        }

        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            return .fallback(unavailableReason())
        }

        let session = await takeSession(model: model)

        do {
            let extracted = try await respond(using: session, caption: trimmedText, onPartial: onPartial)

            return .success(Result(
                parsedCaption: parsedCaption(from: extracted),
                note: "Extracted with Apple Intelligence on this device."
            ))
        } catch {
            do {
                let compactCaption = compactedCaption(from: trimmedText)
                let extracted = try await respond(using: session, caption: compactCaption, onPartial: onPartial)

                return .success(Result(
                    parsedCaption: parsedCaption(from: extracted),
                    note: "Extracted with Apple Intelligence on this device after compacting the caption."
                ))
            } catch {
                return .fallback("The on-device model was available, but structured extraction failed: \(error.localizedDescription)")
            }
        }
    }

    private static func unavailableReason() -> String {
        let availability = SystemLanguageModel.default.availability
        switch availability {
        case .available:
            return "The on-device model was available, but was not used for this import."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is not enabled on this device."
        case .unavailable(.deviceNotEligible):
            return "This device is not eligible for Apple Intelligence."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is available, but the model is not ready yet."
        @unknown default:
            return "Apple Intelligence was unavailable for this import."
        }
    }

    // Streams the structured response, reporting name/address/summary as they
    // are generated so the import sheet can show them live.
    private static func respond(
        using session: LanguageModelSession,
        caption: String,
        onPartial: @escaping @MainActor (ExtractionPreview) -> Void
    ) async throws -> AIExtractedCaption {
        let stream = session.streamResponse(
            to: """
            This is an English social-media caption about a Singapore food/place recommendation.
            Treat lowercase brand names, chef names, street names, mall names, and hashtags as proper nouns, not as a signal that the caption is in another language.

            Caption:
            \(caption)
            """,
            generating: AIExtractedCaption.self,
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 1_200)
        )

        var lastPartial: AIExtractedCaption.PartiallyGenerated?
        for try await snapshot in stream {
            let partial = snapshot.content
            lastPartial = partial
            let preview = ExtractionPreview(
                name: partial.name,
                address: partial.address,
                summary: partial.summary
            )
            await onPartial(preview)
        }

        guard let lastPartial else {
            throw CancellationError()
        }

        return AIExtractedCaption(
            name: lastPartial.name ?? "",
            category: lastPartial.category ?? "",
            address: lastPartial.address ?? "",
            summary: lastPartial.summary ?? "",
            cuisineTags: lastPartial.cuisineTags ?? [],
            foodTags: lastPartial.foodTags ?? [],
            dealDetails: lastPartial.dealDetails ?? [],
            confidence: lastPartial.confidence ?? 0.5
        )
    }

    private static func compactedCaption(from text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map {
                $0
                    .replacingOccurrences(of: #"#\S+"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .prefix(3_000)
            .description
    }

    private static func parsedCaption(from extracted: AIExtractedCaption) -> ParsedCaption {
        let category = category(from: extracted.category)
        let cuisineTags = PlaceTagNormalizer.normalize(extracted.cuisineTags)
        let foodTags = PlaceTagNormalizer.normalize(extracted.foodTags)
        let deals = extracted.dealDetails
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqueCaseInsensitive()
            .map { Deal(title: "Imported deal", details: $0, status: .unknown) }

        let title = sanitized(extracted.name, fallback: defaultTitle(for: category))
        let address = sanitized(extracted.address, fallback: "Singapore")
        let summary = sanitized(
            extracted.summary,
            fallback: "\(title) is a \(category.rawValue.lowercased()) \(address == "Singapore" ? "in Singapore" : "near \(address)")."
        )
        let confidence = min(0.95, max(0.35, extracted.confidence))

        return ParsedCaption(
            title: title,
            category: category,
            cuisineTags: cuisineTags,
            foodTags: foodTags,
            address: address,
            summary: summary,
            notes: deals.map(\.details).joined(separator: "\n"),
            deals: deals,
            confidence: confidence
        )
    }

    private static func sanitized(_ value: String, fallback: String) -> String {
        let trimmed = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func category(from value: String) -> IdeaCategory {
        IdeaCategory.matching(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .restaurant
    }

    private static func defaultTitle(for category: IdeaCategory) -> String {
        "Imported \(category.rawValue.lowercased())"
    }
}

private extension Array where Element == String {
    func uniqueCaseInsensitive() -> [String] {
        reduce(into: [String]()) { result, value in
            let key = value
                .lowercased()
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !result.contains(where: { $0.lowercased() == key }) else { return }
            result.append(value)
        }
    }
}

private enum CaptionIdeaParser {
    static func parse(_ text: String) -> ParsedCaption {
        let lines = text
            .components(separatedBy: .newlines)
            .map { clean($0) }
            .filter { !$0.isEmpty }

        let joined = lines.joined(separator: "\n")
        let lowercased = joined.lowercased()

        let category = category(from: lowercased)
        let cuisineTags = PlaceTagNormalizer.normalize(cuisineTags(from: lowercased, category: category).map(\.rawValue))
        let foodTags = PlaceTagNormalizer.normalize(foodTags(from: lowercased, category: category).map(\.rawValue))
        let title = title(from: lines, joinedText: joined, category: category)
        let address = address(from: lines, joinedText: joined, title: title)
        let deals = deals(from: joined)
        let notes = deals.map(\.details).joined(separator: "\n")
        let summary = summary(for: title, category: category, address: address, lowercasedText: lowercased)

        let filledFields = [
            title != fallbackTitle(for: category),
            address != "Singapore",
            !cuisineTags.isEmpty || !foodTags.isEmpty,
            !deals.isEmpty
        ].filter { $0 }.count

        return ParsedCaption(
            title: title,
            category: category,
            cuisineTags: cuisineTags,
            foodTags: foodTags,
            address: address,
            summary: summary,
            notes: notes,
            deals: deals,
            confidence: text.isEmpty ? 0.35 : min(0.9, 0.45 + (Double(filledFields) * 0.1))
        )
    }

    private static func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{200E}", with: "")
            .replacingOccurrences(of: "\u{200F}", with: "")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: #"^\d{1,3}(,\d{3})?\s+likes,\s+\d{1,3}(,\d{3})?\s+comments\s+-\s+[^:]+:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func category(from text: String) -> IdeaCategory {
        if containsAny(["photobooth", "photo booth", "self photo", "photo studio"], in: text) { return .photobooth }
        if containsAny(["hawker", "food centre", "food center", "kopitiam"], in: text) { return .hawker }
        if containsAny(["restaurant", "sushi", "sashimi", "omakase", "gyukatsu", "katsu", "ribeye", "beef", "oyster", "ramen", "somen"], in: text) { return .restaurant }
        if containsAny(["cafe", "coffee", "brunch", "patisserie", "bakery"], in: text) { return .cafe }
        if containsAny(["ice cream", "gelato", "dessert", "cake", "waffle", "pastry"], in: text) { return .dessertShop }
        if containsAny(["bar", "cocktail", "wine", "speakeasy"], in: text) { return .bar }
        if containsAny(["event", "festival", "exhibition", "pop-up", "popup", "market"], in: text) { return .event }
        if containsAny(["shop", "store", "boutique", "retail"], in: text) { return .shop }
        if containsAny(["activity", "workshop", "class", "escape room", "arcade"], in: text) { return .activity }
        return .restaurant
    }

    private static func cuisineTags(from text: String, category: IdeaCategory) -> [CuisineTag] {
        var values: [CuisineTag] = []

        if containsAny(["japanese", "sushi", "sashimi", "omakase", "ramen", "gyukatsu", "somen", "monaka", "katsu"], in: text) { values.append(.japanese) }
        if containsAny(["italian", "pasta", "pizza"], in: text) { values.append(.italian) }
        if containsAny(["chinese", "dim sum", "dimsum", "hotpot", "hot pot"], in: text) { values.append(.chinese) }
        if containsAny(["korean", "kimchi", "k-bbq", "kbbq"], in: text) { values.append(.korean) }
        if containsAny(["thai", "tom yum", "pad thai"], in: text) { values.append(.thai) }
        if containsAny(["western", "steak", "burger", "sandwich", "fried chicken"], in: text) { values.append(.western) }
        if containsAny(["indian", "biryani", "prata", "naan"], in: text) { values.append(.indian) }
        if containsAny(["malay", "nasi lemak", "rendang"], in: text) { values.append(.malay) }
        if containsAny(["indonesian", "ayam penyet", "bakso"], in: text) { values.append(.indonesian) }
        if containsAny(["vietnamese", "pho", "banh mi"], in: text) { values.append(.vietnamese) }
        if containsAny(["mediterranean", "greek", "middle eastern", "turkish"], in: text) { values.append(.mediterranean) }
        if containsAny(["mexican", "taco", "burrito", "quesadilla"], in: text) { values.append(.mexican) }
        if containsAny(["french", "patisserie", "croissant"], in: text) { values.append(.french) }
        if containsAny(["local", "singaporean", "hawker", "kopitiam"], in: text) || category == .hawker { values.append(.local) }
        if containsAny(["fusion"], in: text) { values.append(.fusion) }
        if containsAny(["dessert", "ice cream", "gelato", "cake", "pastry", "waffle", "matcha"], in: text) || category == .dessertShop { values.append(.dessert) }

        return Array(Set(values)).sorted { $0.rawValue < $1.rawValue }
    }

    private static func foodTags(from text: String, category: IdeaCategory) -> [FoodTag] {
        var values: [FoodTag] = []

        if containsAny(["steak", "ribeye"], in: text) { values.append(.steak) }
        if containsAny(["sushi"], in: text) { values.append(.sushi) }
        if containsAny(["ramen"], in: text) { values.append(.ramen) }
        if containsAny(["gyukatsu"], in: text) { values.append(.gyukatsu) }
        if containsAny(["omakase"], in: text) { values.append(.omakase) }
        if containsAny(["sashimi"], in: text) { values.append(.sashimi) }
        if containsAny(["ice cream"], in: text) { values.append(.iceCream) }
        if containsAny(["fried chicken"], in: text) { values.append(.friedChicken) }
        if containsAny(["sandwich", "sandwiches", "banh mi"], in: text) { values.append(.sandwiches) }
        if containsAny(["pasta"], in: text) { values.append(.pasta) }
        if containsAny(["pizza"], in: text) { values.append(.pizza) }
        if containsAny(["burger", "burgers"], in: text) { values.append(.burgers) }
        if containsAny(["coffee"], in: text) { values.append(.coffee) }
        if containsAny(["matcha"], in: text) { values.append(.matcha) }
        if containsAny(["pastry", "pastries", "croissant"], in: text) { values.append(.pastries) }
        if containsAny(["oyster", "oysters"], in: text) { values.append(.oysters) }
        if containsAny(["beef"], in: text) { values.append(.beef) }
        if containsAny(["noodle", "noodles"], in: text) { values.append(.noodles) }
        if containsAny(["rice"], in: text) { values.append(.rice) }
        if containsAny(["dessert", "cake"], in: text) || category == .dessertShop { values.append(.desserts) }
        if containsAny(["waffle", "waffles"], in: text) { values.append(.waffles) }
        if containsAny(["gelato"], in: text) { values.append(.gelato) }
        if containsAny(["seafood"], in: text) { values.append(.seafood) }
        if containsAny(["hotpot", "hot pot"], in: text) { values.append(.hotpot) }
        if containsAny(["dim sum", "dimsum"], in: text) { values.append(.dimSum) }
        if containsAny(["somen"], in: text) { values.append(.somen) }
        if containsAny(["monaka"], in: text) { values.append(.monaka) }

        return Array(Set(values)).sorted { $0.rawValue < $1.rawValue }
    }

    private static func title(from lines: [String], joinedText: String, category: IdeaCategory) -> String {
        let prefixed = lines.first { line in
            let lower = line.lowercased()
            return lower.hasPrefix("name:")
                || lower.hasPrefix("place:")
                || lower.hasPrefix("restaurant:")
                || lower.hasPrefix("cafe:")
                || lower.hasPrefix("where:")
                || line.hasPrefix("@")
        }

        if let prefixed {
            return stripLabel(prefixed)
        }

        if let introName = placeNameBeforeFirstPin(in: lines) {
            return introName
        }

        let handleName = displayNameFromPlaceHandle(in: joinedText)

        if let locationName = placeNameFromLocationLine(in: lines, handleName: handleName) {
            return locationName
        }

        if let locationName = placeNameFromInlineLocation(in: joinedText, handleName: handleName) {
            return locationName
        }

        if let handleName {
            return handleName
        }

        if let sentenceName = properNameFromSentence(in: lines) {
            return sentenceName
        }

        let ignoredKeywords = ["http", "#", "promo", "deal", "discount", "address", "open", "hours", "singapore", "nearest", "small restaurant"]
        let candidate = lines.first { line in
            line.count <= 80
                && !containsAny(ignoredKeywords, in: line.lowercased())
                && !line.contains(":")
                && !line.hasPrefix("📍")
                && !line.hasPrefix("🍴")
                && !line.hasPrefix("🕌")
                && !line.hasPrefix("💷")
                && !line.hasPrefix("⭐️")
        }

        return candidate.map(foodTitleFallback) ?? fallbackTitle(for: category)
    }

    private static func address(from lines: [String], joinedText: String, title: String) -> String {
        let candidateLines = lines.filter { !isHashtagBlock($0) }

        if let labelledLocation = candidateLines.first(where: isLocationLabelledLine) {
            return normalizeLocation(labelledLocation, removingTitle: title)
        }

        if let pinnedLocations = pinnedLocations(from: joinedText) {
            return normalizeLocation(pinnedLocations, removingTitle: title)
        }

        if let inlineLocation = inlineLocation(from: joinedText) {
            return normalizeLocation(inlineLocation, removingTitle: title)
        }

        if let nearbyLocation = candidateLines.first(where: isNearbyLocationLine) {
            return normalizeLocation(nearbyLocation, removingTitle: title)
        }

        if let postalAddress = candidateLines.first(where: { $0.range(of: #"\b\d{6}\b"#, options: .regularExpression) != nil }) {
            return normalizeLocation(postalAddress, removingTitle: title)
        }

        let singaporeLine = candidateLines.first { line in
            let lower = line.lowercased()
            return lower.contains("singapore")
                && !lower.contains("outside of")
                && !lower.contains("nearest place to pray")
        }

        return singaporeLine.map { normalizeLocation($0, removingTitle: title) } ?? "Singapore"
    }

    private static func deals(from text: String) -> [Deal] {
        dealSnippets(in: text)
            .reduce(into: [String]()) { result, snippet in
                let normalized = snippet.lowercased()
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty, !result.contains(where: { $0.lowercased() == normalized }) else { return }
                result.append(snippet)
            }
            .map { snippet in
                Deal(title: "Imported deal", details: snippet, status: .unknown)
            }
    }

    private static func summary(for title: String, category: IdeaCategory, address: String, lowercasedText: String) -> String {
        let locationPhrase = locationPhrase(for: address)

        if category == .restaurant {
            let menuItems = [
                ("gyukatsu", "gyukatsu"),
                ("a5 ribeye", "A5 ribeye sets"),
                ("miso soup", "miso soup"),
                ("rice", "rice"),
                ("cabbage", "cabbage"),
                ("kimchi", "kimchi"),
                ("mentaiko", "mentaiko mayo fries"),
                ("oyster", "oysters"),
                ("sushi", "sushi"),
                ("monaka", "monaka"),
                ("somen", "somen"),
                ("truffle uni", "truffle uni somen"),
                ("mala salmon", "mala salmon somen"),
                ("coffee", "coffee"),
                ("matcha", "matcha")
            ]
            .compactMap { lowercasedText.contains($0.0) ? $0.1 : nil }

            if !menuItems.isEmpty {
                let certification = lowercasedText.contains("halal") ? "halal-certified " : ""
                return "\(title) is a \(certification)restaurant \(locationPhrase) serving \(menuItems.joined(separator: ", "))."
            }
        }

        switch category {
        case .restaurant:
            return "\(title) is a restaurant \(locationPhrase). Confirm the cuisine, address, and any deal details before saving."
        case .cafe:
            return "\(title) is a cafe \(locationPhrase). Good for a coffee, brunch, or dessert date depending on the menu."
        case .hawker:
            return "\(title) is a hawker or casual food spot \(locationPhrase)."
        case .bar:
            return "\(title) is a bar \(locationPhrase)."
        case .dessertShop:
            return "\(title) is a dessert spot \(locationPhrase)."
        case .activity:
            return "\(title) is an activity-based date idea \(locationPhrase)."
        case .event:
            return "\(title) is an event-based date idea \(locationPhrase). Check dates before visiting."
        case .shop:
            return "\(title) is a shop or retail date idea \(locationPhrase)."
        case .photobooth:
            return "\(title) is a photobooth or self-photo date idea \(locationPhrase)."
        }
    }

    private static func line(containingAny keywords: [String], in lines: [String]) -> String? {
        lines.first { containsAny(keywords, in: $0.lowercased()) }
    }

    private static func containsAny(_ keywords: [String], in text: String) -> Bool {
        keywords.contains { text.contains($0) }
    }

    private static func stripLabel(_ value: String) -> String {
        value
            .replacingOccurrences(of: "📍", with: "")
            .replacingOccurrences(of: #"^(name|place|restaurant|cafe|where|address|location):"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^[\s:•\-\|]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isLocationLabelledLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return line.hasPrefix("📍")
            || lower.hasPrefix("location:")
            || lower.hasPrefix("address:")
            || lower.hasPrefix("where:")
            || lower.hasPrefix("located at:")
            || lower.hasPrefix("located:")
    }

    private static func isNearbyLocationLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.hasPrefix("near ")
            && !lower.contains("nearest place to pray")
            && !lower.contains("nearest prayer")
    }

    private static func isHashtagBlock(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let hashtagCount = trimmed.filter { $0 == "#" }.count
        return trimmed.hasPrefix("#") || hashtagCount >= 2
    }

    private static func normalizeLocation(_ value: String, removingTitle title: String? = nil) -> String {
        var normalized = value
            .replacingOccurrences(of: "📍", with: ", ")
            .replacingOccurrences(of: #"^(address|location|where|located at|located):"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+#.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s+\bprices?\s+in\s+the\s+video!?.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s+\bprice\s+in\s+video!?.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[\s,:•\-\|]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let title, normalized.lowercased().hasPrefix(title.lowercased()) {
            normalized = String(normalized.dropFirst(title.count))
                .replacingOccurrences(of: #"^[\s,:\-]+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return normalized.isEmpty ? "Singapore" : normalized
    }

    private static func locationPhrase(for address: String) -> String {
        if address == "Singapore" {
            return "in Singapore"
        }

        if address.lowercased().hasPrefix("near ") {
            return address
        }

        return "near \(address)"
    }

    private static func displayNameFromPlaceHandle(in text: String) -> String? {
        let patterns = [
            #"(?i)\bfrom\s+\[?@([A-Za-z0-9._]+)"#,
            #"(?i)\bat\s+\[?@([A-Za-z0-9._]+)"#,
            #"(?i)\b(?:visit|try|check(?:\s+them)?\s+out|head\s+down\s+to)\s+\[?@([A-Za-z0-9._]+)"#,
            #"@([A-Za-z0-9._]+)"#
        ]

        for pattern in patterns {
            guard let handle = firstHandle(in: text, pattern: pattern) else { continue }
            let name = displayName(from: handle)
            if !isLikelyCreatorHandle(handle) || pattern != patterns.last {
                return name
            }
        }

        return nil
    }

    private static func placeNameBeforeFirstPin(in lines: [String]) -> String? {
        for line in lines where line.contains("📍") {
            guard let pinRange = line.range(of: "📍") else { continue }
            let intro = String(line[..<pinRange.lowerBound])
            guard let name = placeNameFromIntroSegment(intro) else { continue }
            return name
        }

        return nil
    }

    private static func placeNameFromIntroSegment(_ value: String) -> String? {
        var candidate = value
            .replacingOccurrences(of: #"^.*?:"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"@\S+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let symbolRange = candidate.range(of: #"[\p{So}\p{Sk}]"#, options: .regularExpression) {
            candidate = String(candidate[..<symbolRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let descriptorPattern = #"(?i)\s+\b(?:italian|japanese|korean|thai|chinese|french|mexican|indian|western|halal|street\s+food|food|restaurant|cafe|bar|dessert|brunch|dishes)\b.*$"#
        candidate = candidate
            .replacingOccurrences(of: descriptorPattern, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[\s:•\-\|]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'., ")))

        guard candidate.count >= 3,
              candidate.count <= 60,
              !candidate.contains("#"),
              !candidate.localizedCaseInsensitiveContains("instagram"),
              !isNonVenueIntroName(candidate),
              !isMostlyAddress(candidate) else { return nil }

        return foodTitleFallback(candidate)
    }

    private static func isNonVenueIntroName(_ value: String) -> Bool {
        let lower = value.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\s-]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return lower == "halal certified"
            || lower == "nearest place to pray"
            || lower == "small restaurant"
            || lower == "prices in the video"
            || lower.hasPrefix("nearest ")
            || lower.hasPrefix("near ")
    }

    private static func firstHandle(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { return nil }
        guard let handleRange = Range(match.range(at: 1), in: text) else { return nil }

        return String(text[handleRange])
    }

    private static func displayName(from handle: String) -> String {
        var words = handle
            .lowercased()
            .split(separator: "_")
            .map(String.init)

        if words.last == "sg" {
            words.removeLast()
        } else if words.count == 1, let word = words.first, word.hasSuffix("sg"), word.count > 4 {
            words[0] = String(word.dropLast(2))
        }

        guard !words.isEmpty else { return "Imported Place" }

        return words
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func inlineLocation(from text: String) -> String? {
        let patterns = [
            "📍\\s*:?\\s*([^🍴🕌💷⭐\\n#]+)",
            "(?i)\\blocation\\s*:\\s*([^🍴🕌💷⭐\\n#]+)",
            "(?i)\\baddress\\s*:\\s*([^🍴🕌💷⭐\\n#]+)"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges > 1,
                  let locationRange = Range(match.range(at: 1), in: text) else { continue }

            let location = String(text[locationRange])
                .replacingOccurrences(of: #"[\.;,]\s*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !location.isEmpty {
                return location
            }
        }

        return nil
    }

    private static func pinnedLocations(from text: String) -> String? {
        let parts = text.components(separatedBy: "📍").dropFirst()
        let locations = parts.compactMap(cleanPinnedLocation)

        guard !locations.isEmpty else { return nil }
        return locations.joined(separator: ", ")
    }

    private static func cleanPinnedLocation(_ value: String) -> String? {
        var location = value

        let stopPatterns = [
            #"[🍴🕌💷⭐]"#,
            #"#"#,
            #"(?i)\.\s+(?:they|this|it|if|so|all|i|we|maybe|highly|check|prices?)\b"#,
            #"(?i)\s+prices?\s+in\s+the\s+video!?"#
        ]

        for pattern in stopPatterns {
            guard let range = location.range(of: pattern, options: .regularExpression) else { continue }
            location = String(location[..<range.lowerBound])
        }

        location = location
            .replacingOccurrences(of: #"^[\s:•\-\|,]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'., ")))

        guard location.count >= 3,
              !location.localizedCaseInsensitiveContains("nearest place to pray"),
              !location.localizedCaseInsensitiveContains("nearest prayer") else { return nil }

        return location
    }

    private static func isLikelyCreatorHandle(_ handle: String) -> Bool {
        let lower = handle.lowercased()
        return lower.contains("foodlondon")
            || lower.contains("foodie")
            || lower.contains("eatbook")
            || lower.contains("sethlui")
            || lower.contains("sgfood")
    }

    private static func placeNameFromLocationLine(in lines: [String], handleName: String?) -> String? {
        guard let locationLine = lines.first(where: isLocationLabelledLine) else { return nil }
        let location = normalizeLocation(locationLine)
        return placeNameFromLocationText(location, handleName: handleName)
    }

    private static func placeNameFromInlineLocation(in text: String, handleName: String?) -> String? {
        guard let location = inlineLocation(from: text) else { return nil }
        return placeNameFromLocationText(location, handleName: handleName)
    }

    private static func placeNameFromLocationText(_ location: String, handleName: String?) -> String? {
        let firstPart = location
            .split(separator: ",", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let firstPart,
              firstPart.count >= 3,
              !firstPart.lowercased().hasPrefix("near "),
              !firstPart.lowercased().hasPrefix("nearest "),
              !isMostlyAddress(firstPart) else { return nil }

        if let handleName {
            let words = firstPart.split(separator: " ").map(String.init)
            if let firstWord = words.first, firstWord.localizedCaseInsensitiveCompare(handleName) == .orderedSame {
                return firstWord
            }
        }

        return firstPart
    }

    private static func properNameFromSentence(in lines: [String]) -> String? {
        for line in lines {
            guard line.count <= 140, !isHashtagBlock(line), !isLocationLabelledLine(line) else { continue }
            guard let match = line.range(of: #"\b([A-Z][A-Za-z0-9'&.-]+(?:\s+[A-Z][A-Za-z0-9'&.-]+){1,3})\b"#, options: .regularExpression) else { continue }
            let candidate = String(line[match]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rejected = ["Bugis Junction", "Singapore", "Sultan Mosque", "Sultan Masjid"]
            if !rejected.contains(candidate) {
                return candidate
            }
        }

        return nil
    }

    private static func isMostlyAddress(_ value: String) -> Bool {
        value.range(of: #"\b\d{1,6}\b"#, options: .regularExpression) != nil
            || value.lowercased().contains("singapore")
            || value.lowercased().contains("junction")
            || value.lowercased().contains("mall")
    }

    private static func dealSnippets(in text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ".!?🍴📍🕌⭐\n")
        let segments = text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return segments.compactMap(shortDealSnippet)
    }

    private static func hasConcreteDealEvidence(in text: String) -> Bool {
        text.range(of: #"(?i)(s\$|\$|£|€)\s?\d+(\.\d{1,2})?"#, options: .regularExpression) != nil
            || text.range(of: #"\b\d{1,3}\s?%(\s?off)?\b"#, options: .regularExpression) != nil
            || text.range(of: #"\b(1-for-1|one-for-one|buy\s+\d+\s+get\s+\d+)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            || text.range(of: #"\b(free|complimentary)\b.+\b(with|when|min\.?|minimum|purchase)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            || text.range(of: #"\b(valid|until|till)\b.+\b(\d{1,2}\s?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)|\d{1,2}/\d{1,2})\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            || text.range(of: #"\b(promo code|use code|code:)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func shortDealSnippet(from segment: String) -> String? {
        let trimmed = segment
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard hasConcreteDealEvidence(in: trimmed) else { return nil }

        let patterns = [
            #"(?i)(?:s\$|\$|£|€)\s?\d+(?:\.\d{1,2})?(?:\s*(?:for|/|per|nett|\+\+)\s*)?[^#,.!?🍴📍🕌⭐\n"]{0,90}"#,
            #"(?i)\b\d{1,3}\s?%(\s?off)?[^#,.!?🍴📍🕌⭐\n"]{0,80}"#,
            #"(?i)\b(?:1-for-1|one-for-one|buy\s+\d+\s+get\s+\d+)[^#,.!?🍴📍🕌⭐\n"]{0,80}"#,
            #"(?i)\b(?:promo code|use code|code:)\s*[A-Z0-9_-]{2,20}"#
        ]

        for pattern in patterns {
            guard let range = trimmed.range(of: pattern, options: .regularExpression) else { continue }
            let snippet = String(trimmed[range])
                .replacingOccurrences(of: #"\s+#.*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-\"'"))

            if snippet.count >= 4, snippet.count <= 120 {
                return snippet
            }
        }

        return nil
    }

    private static func foodTitleFallback(_ value: String) -> String {
        stripLabel(value)
            .replacingOccurrences(of: #"from\s+\[?@[A-Za-z0-9._]+\]?\([^)]+\)"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"from\s+@[A-Za-z0-9._]+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"[^A-Za-z0-9 '&-]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fallbackTitle(for category: IdeaCategory) -> String {
        switch category {
        case .restaurant: return "Review imported restaurant"
        case .cafe: return "Review imported cafe"
        case .hawker: return "Review imported hawker spot"
        case .bar: return "Review imported bar"
        case .dessertShop: return "Review imported dessert spot"
        case .activity: return "Review imported activity"
        case .event: return "Review imported event"
        case .shop: return "Review imported shop"
        case .photobooth: return "Review imported photobooth"
        }
    }
}
