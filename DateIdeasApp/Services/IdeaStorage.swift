import Foundation

protocol IdeaStorage {
    func loadIdeas() -> [DateIdea]
    func saveIdeas(_ ideas: [DateIdea])
}

struct UserDefaultsIdeaStorage: IdeaStorage {
    private let key = "dateIdeas.savedIdeas"
    private let defaults = UserDefaults.standard

    func loadIdeas() -> [DateIdea] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder.dateIdeas.decode([DateIdea].self, from: data)) ?? []
    }

    func saveIdeas(_ ideas: [DateIdea]) {
        guard let data = try? JSONEncoder.dateIdeas.encode(ideas) else { return }
        defaults.set(data, forKey: key)
    }
}

extension JSONEncoder {
    static var dateIdeas: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var dateIdeas: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

