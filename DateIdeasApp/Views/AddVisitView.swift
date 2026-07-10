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

// Read-only view of a logged visit; editing is an explicit action from here.
struct VisitDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DateIdeaStore
    @EnvironmentObject private var collaborationStore: CollaborationStore

    let idea: DateIdea
    let visit: Visit

    @State private var showingEdit = false
    @State private var previewPhoto: VisitPhotoPreviewItem?

    // Always show the latest saved values, e.g. right after an edit.
    private var currentVisit: Visit {
        store.ideas.first { $0.id == idea.id }?.visits.first { $0.id == visit.id } ?? visit
    }

    private var contributorName: String? {
        guard collaborationStore.activeWorkbook?.isPersonal == false else { return nil }
        return currentVisit.addedByDisplayName
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                ratingSection

                if currentVisit.amountSpent != nil || !currentVisit.notes.isEmpty {
                    detailsSection
                }

                photosSection
            }
            .navigationTitle("Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Edit") {
                        showingEdit = true
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(Theme.accent)
        .sheet(isPresented: $showingEdit) {
            AddVisitView(idea: idea, visit: currentVisit) { updatedVisit in
                store.updateVisit(collaborationStore.stampedVisit(updatedVisit), in: idea)
            }
        }
        .fullScreenCover(item: $previewPhoto) { item in
            VisitPhotoFullScreenView(photoName: item.id)
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                if let title = currentVisit.title, !title.isEmpty {
                    Text(title)
                        .font(.title3.weight(.semibold))

                    Text(currentVisit.visitedAt.formatted(date: .long, time: .omitted))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(currentVisit.visitedAt.formatted(date: .long, time: .omitted))
                        .font(.title3.weight(.semibold))
                }

                if let contributorName {
                    HStack(spacing: 6) {
                        ContributorAvatar(name: contributorName, imageURL: currentVisit.addedByPhotoURL, size: 18)

                        Text("Visited by \(contributorName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Visited by \(contributorName)")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var ratingSection: some View {
        Section("Rating") {
            HStack {
                Text("Overall")
                    .font(.headline)

                Spacer()

                Label(
                    currentVisit.review.overallScore.formatted(.number.precision(.fractionLength(1))),
                    systemImage: "star.fill"
                )
                .font(.title3.weight(.semibold))
                .foregroundStyle(.yellow)
            }

            RatingDisplayRow(title: "Food", value: currentVisit.review.food)
            RatingDisplayRow(title: "Ambience", value: currentVisit.review.ambience)
            RatingDisplayRow(title: "Value", value: currentVisit.review.value)
            RatingDisplayRow(title: "Service", value: currentVisit.review.service)
            RatingDisplayRow(title: "Revisit", value: currentVisit.review.revisitPotential)
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            if let amountSpent = currentVisit.amountSpent {
                HStack {
                    Text("Spent")

                    Spacer()

                    Text(amountSpent.formatted(.currency(code: "SGD")))
                        .foregroundStyle(.secondary)
                }
            }

            if !currentVisit.notes.isEmpty {
                Text(currentVisit.notes)
            }
        }
    }

    @ViewBuilder
    private var photosSection: some View {
        let localPhotos = currentVisit.localPhotoNames

        if !localPhotos.isEmpty {
            Section("Photos") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], spacing: 6) {
                    ForEach(localPhotos, id: \.self) { name in
                        if let url = DateIdeaImageStore.fileURL(for: name),
                           let image = UIImage(contentsOfFile: url.path) {
                            Button {
                                previewPhoto = VisitPhotoPreviewItem(id: name)
                            } label: {
                                Color.clear
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Visit photo, tap to enlarge")
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } else if !currentVisit.photoNames.isEmpty {
            Section("Photos") {
                Label("\(currentVisit.photoNames.count) photo\(currentVisit.photoNames.count == 1 ? "" : "s") on your partner's device", systemImage: "photo.on.rectangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct VisitPhotoPreviewItem: Identifiable {
    let id: String
}

struct VisitPhotoFullScreenView: View {
    @Environment(\.dismiss) private var dismiss
    let photoName: String

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let url = DateIdeaImageStore.fileURL(for: photoName),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .accessibilityLabel("Close photo")
        }
        .onTapGesture {
            dismiss()
        }
    }
}

struct RatingDisplayRow: View {
    let title: String
    let value: Int

    var body: some View {
        HStack {
            Text(title)

            Spacer()

            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { index in
                    Image(systemName: index <= value ? "star.fill" : "star")
                        .font(.footnote)
                        .foregroundStyle(.yellow)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value) out of 5 stars")
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
