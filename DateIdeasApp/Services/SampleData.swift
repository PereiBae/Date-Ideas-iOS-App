import Foundation

enum SampleData {
    static let ideas: [DateIdea] = [
        DateIdea(
            title: "Le Matin Patisserie",
            category: .cafe,
            cuisineTagNames: ["French", "Dessert"],
            foodTagNames: ["Pastries", "Desserts", "Coffee"],
            location: PlaceLocation(
                name: "Le Matin Patisserie",
                address: "2 Orchard Turn, B2-49 ION Orchard, Singapore 238801",
                latitude: 1.3040,
                longitude: 103.8318,
                websiteURL: URL(string: "https://lematin.sg"),
                phoneNumber: nil,
                openingHoursSummary: "Daily, 10:00 AM - 9:30 PM"
            ),
            factualSummary: "French-style pastries and plated desserts in Orchard. Good for a polished dessert or coffee date.",
            notes: "Check queue before heading down.",
            deals: [
                Deal(title: "Weekday pastry set", details: "Imported deal example. Confirm current availability before visiting.", status: .unknown)
            ],
            sourcePosts: []
        ),
        DateIdea(
            title: "Dollop Automat Self Photo Studio",
            category: .photobooth,
            cuisineTagNames: [],
            foodTagNames: [],
            location: PlaceLocation(
                name: "Dollop Automat Self Photo Studio",
                address: "30A Seah Street, Singapore 188386",
                latitude: 1.2965,
                longitude: 103.8547,
                websiteURL: nil,
                phoneNumber: nil,
                openingHoursSummary: "Check booking slots before visiting."
            ),
            factualSummary: "Self photo studio for quick couple portraits. Good as an add-on before dinner nearby.",
            notes: "",
            deals: [],
            sourcePosts: [],
            visits: [
                Visit(
                    amountSpent: Decimal(35),
                    notes: "Fun and easy. Worth doing again for special occasions.",
                    review: Review(food: 3, ambience: 4, value: 4, service: 4, revisitPotential: 5)
                )
            ]
        )
    ]
}
