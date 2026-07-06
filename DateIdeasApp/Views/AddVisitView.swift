import PhotosUI
import SwiftUI

struct AddVisitView: View {
    @Environment(\.dismiss) private var dismiss

    let idea: DateIdea
    let onSave: (Visit) -> Void
    private let existingVisit: Visit?

    @State private var visitedAt = Date()
    @State private var amountSpent = ""
    @State private var notes = ""
    @State private var review = Review()
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoNames: [String] = []

    init(idea: DateIdea, visit: Visit? = nil, onSave: @escaping (Visit) -> Void) {
        self.idea = idea
        self.existingVisit = visit
        self.onSave = onSave
        _visitedAt = State(initialValue: visit?.visitedAt ?? .now)
        _amountSpent = State(initialValue: visit?.amountSpent.map { String(describing: $0) } ?? "")
        _notes = State(initialValue: visit?.notes ?? "")
        _review = State(initialValue: visit?.review ?? Review())
        _photoNames = State(initialValue: visit?.photoNames ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Visit") {
                    DatePicker("Date", selection: $visitedAt, displayedComponents: .date)
                    TextField("Amount spent", text: $amountSpent)
                        .keyboardType(.decimalPad)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                    PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 12, matching: .images) {
                        Label(photoLabel, systemImage: "photo.on.rectangle")
                    }
                }

                Section("Review") {
                    RatingRow(title: "Food", value: $review.food)
                    RatingRow(title: "Ambience", value: $review.ambience)
                    RatingRow(title: "Value", value: $review.value)
                    RatingRow(title: "Service", value: $review.service)
                    RatingRow(title: "Revisit", value: $review.revisitPotential)

                    HStack {
                        Text("Overall")
                        Spacer()
                        Text(review.overallScore.formatted(.number.precision(.fractionLength(1))))
                            .font(.headline)
                    }
                }
            }
            .navigationTitle(existingVisit == nil ? "Add Visit" : "Edit Visit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let spent = Decimal(string: amountSpent)
                        let nextPhotoNames = photoNames + selectedPhotos.map { _ in UUID().uuidString }
                        onSave(Visit(
                            id: existingVisit?.id ?? UUID(),
                            visitedAt: visitedAt,
                            amountSpent: spent,
                            notes: notes,
                            photoNames: nextPhotoNames,
                            review: review
                        ))
                        dismiss()
                    }
                }
            }
        }
    }

    private var photoLabel: String {
        let count = photoNames.count + selectedPhotos.count
        return count == 0 ? "Photos" : "\(count) selected"
    }
}

struct RatingRow: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { index in
                    Button {
                        value = index
                    } label: {
                        Image(systemName: index <= value ? "star.fill" : "star")
                            .foregroundStyle(.yellow)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) \(index) stars")
                }
            }
        }
    }
}
