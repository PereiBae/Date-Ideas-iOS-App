import PhotosUI
import SwiftUI
import UIKit

struct AddVisitView: View {
    @Environment(\.dismiss) private var dismiss

    let idea: DateIdea
    let onSave: (Visit) -> Void
    private let existingVisit: Visit?

    @State private var title = ""
    @State private var visitedAt = Date()
    @State private var amountSpent = ""
    @State private var notes = ""
    @State private var review = Review()
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoNames: [String] = []
    @State private var isSaving = false

    init(idea: DateIdea, visit: Visit? = nil, onSave: @escaping (Visit) -> Void) {
        self.idea = idea
        self.existingVisit = visit
        self.onSave = onSave
        _title = State(initialValue: visit?.title ?? "")
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
                    TextField("Title (optional, e.g. Anniversary dinner)", text: $title)

                    DatePicker("Date", selection: $visitedAt, displayedComponents: .date)

                    TextField("Amount spent", text: $amountSpent)
                        .keyboardType(.decimalPad)

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)

                    PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 12, matching: .images) {
                        Label(photoLabel, systemImage: "photo.on.rectangle")
                    }

                    if !savedLocalPhotoNames.isEmpty {
                        VisitPhotoStrip(photoNames: savedLocalPhotoNames, size: 64) { name in
                            photoNames.removeAll { $0 == name }
                        }
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
            .keyboardDismissal()
            .navigationTitle(existingVisit == nil ? "Add Visit" : "Edit Visit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await save()
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .tint(Theme.accent)
    }

    private var photoLabel: String {
        let count = photoNames.count + selectedPhotos.count
        return count == 0 ? "Add photos" : "\(count) photo\(count == 1 ? "" : "s") selected"
    }

    private var savedLocalPhotoNames: [String] {
        photoNames.filter { name in
            guard let url = DateIdeaImageStore.fileURL(for: name) else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }
    }

    // Writes the picked images to disk so they can actually be shown later.
    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }

        var nextPhotoNames = photoNames
        for item in selectedPhotos {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let name = DateIdeaImageStore.save(data: data) else { continue }
            nextPhotoNames.append(name)
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(Visit(
            id: existingVisit?.id ?? UUID(),
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            visitedAt: visitedAt,
            amountSpent: Decimal(string: amountSpent),
            notes: notes,
            photoNames: nextPhotoNames,
            review: review
        ))
        dismiss()
    }
}

struct VisitPhotoStrip: View {
    let photoNames: [String]
    var size: CGFloat = 56
    var onRemove: ((String) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(photoNames, id: \.self) { name in
                    if let url = DateIdeaImageStore.fileURL(for: name),
                       let image = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) {
                                if let onRemove {
                                    Button {
                                        onRemove(name)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.footnote)
                                            .foregroundStyle(.white, .black.opacity(0.55))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(3)
                                    .accessibilityLabel("Remove photo")
                                }
                            }
                            .accessibilityLabel("Visit photo")
                    }
                }
            }
        }
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
