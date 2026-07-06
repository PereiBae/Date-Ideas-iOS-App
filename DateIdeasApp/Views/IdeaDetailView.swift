import MapKit
import SwiftUI

struct IdeaDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DateIdeaStore
    @State private var showingVisitSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingEditSheet = false
    @State private var editingVisit: Visit?

    let idea: DateIdea

    var currentIdea: DateIdea {
        store.ideas.first(where: { $0.id == idea.id }) ?? idea
    }

    var body: some View {
        List {
            Section {
                IdeaCoverImage(imageName: currentIdea.imageName, url: currentIdea.imageURL)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(currentIdea.category.rawValue)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(Capsule())

                    Text(currentIdea.factualSummary)
                        .font(.body)

                    TagWrap(tags: currentIdea.displayTagTitles)
                }
            }

            Section("Location") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(currentIdea.location.address)
                        .font(.subheadline)

                    PlaceMapView(location: currentIdea.location)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if let website = currentIdea.location.websiteURL {
                    Link(destination: website) {
                        Label("Website", systemImage: "safari")
                    }
                }
            }

            if !currentIdea.activeDeals.isEmpty {
                Section("Current Deals") {
                    ForEach(currentIdea.activeDeals) { deal in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(deal.title)
                                .font(.headline)
                            Text(deal.details)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            DealStatusLine(deal: deal)
                        }
                    }
                }
            }

            if !currentIdea.deals.filter({ !$0.isVisible }).isEmpty {
                Section("Deal History") {
                    ForEach(currentIdea.deals.filter { !$0.isVisible }) { deal in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(deal.title)
                                .font(.headline)
                            Text(deal.details)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            DealStatusLine(deal: deal)
                        }
                    }
                }
            }

            Section("Visits") {
                if currentIdea.visits.isEmpty {
                    Text("Not visited yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(currentIdea.visits) { visit in
                        Button {
                            editingVisit = visit
                        } label: {
                            VisitRowView(visit: visit)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        store.deleteVisits(at: offsets, from: currentIdea)
                    }
                }

                Button {
                    showingVisitSheet = true
                } label: {
                    Label("Add Visit", systemImage: "plus.circle")
                }
            }

            if !currentIdea.sourcePosts.isEmpty {
                Section("Sources") {
                    ForEach(currentIdea.sourcePosts) { post in
                        Link(destination: post.url) {
                            Label(post.platform, systemImage: "link")
                        }
                    }
                }
            }
        }
        .navigationTitle(currentIdea.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingEditSheet = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("Delete this date idea?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Date Idea", role: .destructive) {
                store.deleteIdea(currentIdea)
                dismiss()
            }
        } message: {
            Text("This removes the place, deals, source links, visits, notes, and reviews from this device.")
        }
        .sheet(isPresented: $showingVisitSheet) {
            AddVisitView(idea: currentIdea) { visit in
                store.addVisit(visit, to: currentIdea)
            }
        }
        .sheet(item: $editingVisit) { visit in
            AddVisitView(idea: currentIdea, visit: visit) { updatedVisit in
                store.updateVisit(updatedVisit, in: currentIdea)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditIdeaView(idea: currentIdea) { updatedIdea in
                store.updateIdea(updatedIdea)
            }
        }
    }
}

struct TagWrap: View {
    let tags: [String]

    var body: some View {
        ViewThatFits {
            HStack {
                ForEach(tags, id: \.self) { tag in
                    TagPill(title: tag)
                }
            }

            VStack(alignment: .leading) {
                ForEach(tags, id: \.self) { tag in
                    TagPill(title: tag)
                }
            }
        }
    }
}

struct EditIdeaView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var idea: DateIdea

    let onSave: (DateIdea) -> Void

    init(idea: DateIdea, onSave: @escaping (DateIdea) -> Void) {
        _idea = State(initialValue: idea)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $idea.title)

                    Picker("Type", selection: $idea.category) {
                        ForEach(IdeaCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }

                    TextField("Summary", text: $idea.factualSummary, axis: .vertical)
                        .lineLimit(3...6)

                    TextField("Notes", text: $idea.notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section("Location") {
                    TextField("Place name", text: $idea.location.name)
                    TextField("Address", text: $idea.location.address, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Image") {
                    TextField("Image URL", text: Binding(
                        get: { idea.imageURL?.absoluteString ?? "" },
                        set: { value in
                            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            idea.imageURL = trimmed.isEmpty ? nil : URL(string: trimmed)
                        }
                    ))
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()

                    IdeaCoverImage(imageName: idea.imageName, url: idea.imageURL)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Section("Cuisine") {
                    ForEach(CuisineTag.allCases) { tag in
                        Toggle(tag.rawValue, isOn: Binding(
                            get: { idea.cuisineTags.contains(tag) },
                            set: { isSelected in
                                if isSelected {
                                    idea.cuisineTags.append(tag)
                                } else {
                                    idea.cuisineTags.removeAll { $0 == tag }
                                }
                            }
                        ))
                    }
                }

                Section("Food Items") {
                    ForEach(FoodTag.allCases) { tag in
                        Toggle(tag.rawValue, isOn: Binding(
                            get: { idea.foodTags.contains(tag) },
                            set: { isSelected in
                                if isSelected {
                                    idea.foodTags.append(tag)
                                } else {
                                    idea.foodTags.removeAll { $0 == tag }
                                }
                            }
                        ))
                    }
                }

                Section("Deals") {
                    if idea.deals.isEmpty {
                        Text("No deals saved")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($idea.deals) { $deal in
                            DealEditorRows(deal: $deal)
                        }
                        .onDelete { offsets in
                            idea.deals.remove(atOffsets: offsets)
                        }
                    }

                    Button {
                        idea.deals.append(Deal(title: "", details: "", status: .unknown))
                    } label: {
                        Label("Add Deal", systemImage: "tag")
                    }
                }
            }
            .navigationTitle("Edit Place")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if idea.location.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            idea.location.name = idea.title
                        }
                        onSave(idea)
                        dismiss()
                    }
                    .disabled(idea.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct TagPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(Capsule())
    }
}

struct DealStatusLine: View {
    let deal: Deal

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: deal.isExpired ? "xmark.circle.fill" : deal.isEndingSoon ? "clock.badge.exclamationmark.fill" : "tag.fill")
            Text(deal.countdownText ?? deal.status.label)
            if let endsAt = deal.endsAt {
                Text("•")
                Text(endsAt, style: .date)
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        if deal.isExpired { return .secondary }
        if deal.isEndingSoon { return .orange }
        return .green
    }
}

struct DealEditorRows: View {
    @Binding var deal: Deal
    @State private var hasStartDate: Bool
    @State private var hasEndDate: Bool

    init(deal: Binding<Deal>) {
        _deal = deal
        _hasStartDate = State(initialValue: deal.wrappedValue.startsAt != nil)
        _hasEndDate = State(initialValue: deal.wrappedValue.endsAt != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Deal title", text: $deal.title)
            TextField("Details", text: $deal.details, axis: .vertical)
                .lineLimit(2...5)

            Toggle("Has start date", isOn: Binding(
                get: { hasStartDate },
                set: { isOn in
                    hasStartDate = isOn
                    deal.startsAt = isOn ? (deal.startsAt ?? .now) : nil
                }
            ))

            if hasStartDate {
                DatePicker("Starts", selection: Binding(
                    get: { deal.startsAt ?? .now },
                    set: { deal.startsAt = $0 }
                ), displayedComponents: .date)
            }

            Toggle("Has end date", isOn: Binding(
                get: { hasEndDate },
                set: { isOn in
                    hasEndDate = isOn
                    deal.endsAt = isOn ? (deal.endsAt ?? .now) : nil
                }
            ))

            if hasEndDate {
                DatePicker("Ends", selection: Binding(
                    get: { deal.endsAt ?? .now },
                    set: { deal.endsAt = $0 }
                ), displayedComponents: .date)
            }

            Picker("Status", selection: $deal.status) {
                Text("Unknown").tag(DealStatus.unknown)
                Text("Active").tag(DealStatus.active)
                Text("Confirm").tag(DealStatus.needsConfirmation)
                Text("Expired").tag(DealStatus.expired)
            }

            if let countdown = deal.countdownText {
                Label(countdown, systemImage: deal.isEndingSoon ? "clock.badge.exclamationmark" : "clock")
                    .font(.caption)
                    .foregroundStyle(deal.isEndingSoon ? .orange : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct PlaceMapView: View {
    let location: PlaceLocation

    var body: some View {
        if let latitude = location.latitude, let longitude = location.longitude {
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            let region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )

            Map(initialPosition: .region(region)) {
                Marker(location.name, coordinate: coordinate)
                    .tint(.red)
            }
        } else {
            ContentUnavailableView("Map unavailable", systemImage: "map")
        }
    }
}

struct VisitRowView: View {
    let visit: Visit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(visit.visitedAt, style: .date)
                    .font(.headline)
                Spacer()
                Label(visit.review.overallScore.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                    .foregroundStyle(.yellow)
            }

            if let amountSpent = visit.amountSpent {
                Text("Spent \(amountSpent.formatted(.currency(code: "SGD")))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !visit.notes.isEmpty {
                Text(visit.notes)
                    .font(.subheadline)
            }

            if !visit.photoNames.isEmpty {
                Label("\(visit.photoNames.count) photos", systemImage: "photo.on.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
