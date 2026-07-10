import MapKit
import SwiftUI

struct IdeaDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: DateIdeaStore
    @EnvironmentObject private var collaborationStore: CollaborationStore
    @State private var showingVisitSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingEditSheet = false
    @State private var viewingVisit: Visit?
    @State private var copiedWorkbookName: String?
    @State private var placeDetailItem: MKMapItem?
    @State private var isLoadingPlaceDetail = false

    let idea: DateIdea

    var currentIdea: DateIdea {
        store.ideas.first(where: { $0.id == idea.id }) ?? idea
    }

    private var otherWorkbooks: [Workbook] {
        guard collaborationStore.canUseFirebase else { return [] }
        return collaborationStore.workbooks.filter { $0.id != collaborationStore.activeWorkbook?.id }
    }

    var body: some View {
        List {
            heroSection
            titleSection

            if !currentIdea.activeDeals.isEmpty {
                dealsSection
            }

            locationSection
            visitsSection

            if !currentIdea.sourcePosts.isEmpty {
                sourcesSection
            }

            if !currentIdea.deals.filter({ !$0.isVisible }).isEmpty {
                dealHistorySection
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    if !otherWorkbooks.isEmpty {
                        Menu {
                            ForEach(otherWorkbooks) { workbook in
                                Button {
                                    copy(to: workbook)
                                } label: {
                                    Label(workbook.name, systemImage: workbook.isPersonal ? "lock" : "person.2")
                                }
                            }
                        } label: {
                            Label("Copy to workbook", systemImage: "doc.on.doc")
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let copiedWorkbookName {
                Label("Copied to \(copiedWorkbookName)", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sensoryFeedback(.success, trigger: copiedWorkbookName) { _, newValue in
            newValue != nil
        }
        .task(id: copiedWorkbookName) {
            guard copiedWorkbookName != nil else { return }
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled {
                withAnimation(.smooth(duration: 0.25)) {
                    copiedWorkbookName = nil
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
                store.addVisit(collaborationStore.stampedVisit(visit), to: currentIdea)
            }
        }
        .sheet(item: $viewingVisit) { visit in
            VisitDetailView(idea: currentIdea, visit: visit)
        }
        .sheet(isPresented: $showingEditSheet) {
            EditIdeaView(idea: currentIdea) { updatedIdea in
                store.updateIdea(updatedIdea)
            }
        }
        .mapItemDetailSheet(item: $placeDetailItem)
    }

    // MARK: Hero

    private var heroSection: some View {
        Section {
            heroImage
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var heroImage: some View {
        let cover = IdeaCoverImage(imageName: currentIdea.imageName, url: currentIdea.imageURL)
            .frame(height: 230)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .topTrailing) {
                statusBadge
                    .padding(10)
            }
            .overlay(alignment: .bottomLeading) {
                categoryBadge
                    .padding(10)
            }

        if let post = currentIdea.sourcePosts.first {
            Button {
                openURL(post.url)
            } label: {
                cover
                    .overlay(alignment: .bottomTrailing) {
                        HStack(spacing: 4) {
                            Text("View post")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                        .padding(10)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cover photo. Opens the original \(post.platform) post.")
        } else {
            cover
        }
    }

    private var statusBadge: some View {
        Label(
            currentIdea.hasVisited ? "Visited" : "Want to go",
            systemImage: currentIdea.hasVisited ? "checkmark.circle.fill" : "heart.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(currentIdea.hasVisited ? Color.green : Color.red, in: Capsule())
    }

    private var categoryBadge: some View {
        Label(currentIdea.category.rawValue, systemImage: currentIdea.category.systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
    }

    // MARK: Title, actions, summary

    private var titleSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentIdea.title)
                        .font(.placeTitle(.title2))

                    Text(currentIdea.location.address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let contributor = currentIdea.createdByDisplayName {
                    HStack(spacing: 6) {
                        ContributorAvatar(name: contributor, imageURL: currentIdea.createdByPhotoURL, size: 18)

                        Text("Added by \(contributor) · \(currentIdea.createdAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Added by \(contributor)")
                }

                actionRow

                if !currentIdea.factualSummary.isEmpty {
                    Text(currentIdea.factualSummary)
                        .font(.body)
                }

                if !currentIdea.displayTagTitles.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(currentIdea.displayTagTitles, id: \.self) { tag in
                            TagPill(title: tag)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                showingVisitSheet = true
            } label: {
                Label("Log visit", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)

            Button {
                openDirections()
            } label: {
                Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)

            if let website = currentIdea.location.websiteURL {
                Button {
                    openURL(website)
                } label: {
                    Image(systemName: "safari")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Website")
            }
        }
        .buttonBorderShape(.capsule)
    }

    // MARK: Deals

    private var dealsSection: some View {
        Section("Current deals") {
            ForEach(currentIdea.activeDeals) { deal in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "tag.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(deal.title.isEmpty ? "Deal" : deal.title)
                            .font(.subheadline.weight(.semibold))

                        Text(deal.details)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        DealStatusLine(deal: deal)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var expiredDeals: [Deal] {
        currentIdea.deals.filter { !$0.isVisible }
    }

    private var dealHistorySection: some View {
        Section {
            DisclosureGroup("Deal history (\(expiredDeals.count))") {
                ForEach(expiredDeals) { deal in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(deal.title.isEmpty ? "Deal" : deal.title)
                            .font(.subheadline.weight(.semibold))

                        Text(deal.details)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        DealStatusLine(deal: deal)
                    }
                    .padding(.vertical, 2)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Location

    private var locationSection: some View {
        Section("Location") {
            VStack(alignment: .leading, spacing: 10) {
                PlaceMapView(location: currentIdea.location)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Label(currentIdea.location.address, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            Button {
                showPlaceDetails()
            } label: {
                HStack {
                    Label("Opening hours & info", systemImage: "clock")

                    Spacer()

                    if isLoadingPlaceDetail {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .disabled(isLoadingPlaceDetail)
        }
    }

    // Looks the place up in Apple Maps and presents its place card
    // (opening hours, photos, phone) via MapKit's place detail sheet.
    private func showPlaceDetails() {
        guard !isLoadingPlaceDetail else { return }
        isLoadingPlaceDetail = true

        Task {
            defer { isLoadingPlaceDetail = false }

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = "\(currentIdea.title), \(currentIdea.location.address)"
            if let latitude = currentIdea.location.latitude, let longitude = currentIdea.location.longitude {
                request.region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            }

            let response = try? await MKLocalSearch(request: request).start()
            placeDetailItem = response?.mapItems.first
        }
    }

    // MARK: Visits

    private var visitsSection: some View {
        Section {
            if currentIdea.visits.isEmpty {
                Text("Not visited yet — log your first visit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(currentIdea.visits) { visit in
                    Button {
                        viewingVisit = visit
                    } label: {
                        HStack(spacing: 10) {
                            VisitRowView(visit: visit)

                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    store.deleteVisits(at: offsets, from: currentIdea)
                }
            }
        } header: {
            HStack {
                Text("Visits")

                Spacer()

                Button {
                    showingVisitSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: Sources

    private var sourcesSection: some View {
        Section("From") {
            FlowLayout(spacing: 8) {
                ForEach(currentIdea.sourcePosts) { post in
                    Button {
                        openURL(post.url)
                    } label: {
                        HStack(spacing: 5) {
                            Text(post.platform)

                            Image(systemName: "arrow.up.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background {
                            Capsule().fill(Color(.tertiarySystemGroupedBackground))
                            Capsule().strokeBorder(Color(.separator), lineWidth: 0.5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: Actions

    private func openDirections() {
        let location = currentIdea.location

        if let latitude = location.latitude, let longitude = location.longitude {
            let mapItem = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
            mapItem.name = location.name.isEmpty ? currentIdea.title : location.name
            mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
        } else {
            let query = "\(currentIdea.title) \(location.address)"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "maps://?q=\(query)") {
                openURL(url)
            }
        }
    }

    private func copy(to workbook: Workbook) {
        Task {
            await collaborationStore.copyIdea(currentIdea, to: workbook)
            if collaborationStore.errorMessage == nil {
                withAnimation(.smooth(duration: 0.25)) {
                    copiedWorkbookName = workbook.name
                }
            }
        }
    }

}

struct EditIdeaView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var idea: DateIdea
    @State private var keyboardVisible = false

    let onSave: (DateIdea) -> Void

    init(idea: DateIdea, onSave: @escaping (DateIdea) -> Void) {
        _idea = State(initialValue: idea)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                heroSection
                detailsSection
                locationSection
                cuisineSection
                foodSection
                dealsSection
            }
            .keyboardDismissal()
            .navigationTitle("Edit Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Stays at the page bottom: hidden behind the keyboard while
                // typing rather than floating above it.
                if !keyboardVisible {
                    saveBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .observesKeyboardVisibility($keyboardVisible)
        }
        .tint(Theme.accent)
    }

    private var heroSection: some View {
        Section {
            IdeaCoverImage(imageName: idea.imageName, url: idea.imageURL)
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

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
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Name", text: $idea.title)
                .font(.placeTitle(.body))

            Picker("Type", selection: $idea.category) {
                ForEach(IdeaCategory.allCases) { category in
                    Label(category.rawValue, systemImage: category.systemImage)
                        .tag(category)
                }
            }
            // Pushed list style: icons on every row, selection tick trailing.
            .pickerStyle(.navigationLink)
            // Keep row separators full width (Label rows shift them otherwise).
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }

            TextField("Summary", text: $idea.factualSummary, axis: .vertical)
                .lineLimit(3...6)

            TextField("Notes", text: $idea.notes, axis: .vertical)
                .lineLimit(2...6)
        }
    }

    private var locationSection: some View {
        Section("Location") {
            TextField("Address", text: $idea.location.address, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    private var cuisineSection: some View {
        Section("Cuisine") {
            EditableTagChips(tags: $idea.cuisineTagNames, addPrompt: "Add a cuisine (e.g. Korean)")
        }
    }

    private var foodSection: some View {
        Section("Food items") {
            EditableTagChips(tags: $idea.foodTagNames, addPrompt: "Add a dish or drink (e.g. Ramyun)")
        }
    }

    private var dealsSection: some View {
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

    private var saveBar: some View {
        Button(action: save) {
            Text("Save changes")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(idea.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func save() {
        if idea.location.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            idea.location.name = idea.title
        }
        onSave(idea)
        dismiss()
    }

}

struct TagPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
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
        VStack(alignment: .leading, spacing: 14) {
            TextField("Deal title", text: $deal.title)
                .font(.headline)

            TextField("Details", text: $deal.details, axis: .vertical)
                .lineLimit(2...5)

            Toggle("Has start date", isOn: Binding(
                get: { hasStartDate },
                set: { isOn in
                    hasStartDate = isOn
                    deal.startsAt = isOn ? (deal.startsAt ?? .now) : nil
                }
            ))
            .padding(.vertical, 2)

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
            .padding(.vertical, 2)

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
    @EnvironmentObject private var collaborationStore: CollaborationStore
    let visit: Visit

    private var contributorName: String? {
        guard collaborationStore.activeWorkbook?.isPersonal == false else { return nil }
        return visit.addedByDisplayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    if let title = visit.title, !title.isEmpty {
                        Text(title)
                            .font(.headline)

                        Text(visit.visitedAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(visit.visitedAt, style: .date)
                            .font(.headline)
                    }
                }

                Spacer()

                Label(visit.review.overallScore.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                    .foregroundStyle(.yellow)
            }

            if let contributorName {
                HStack(spacing: 6) {
                    ContributorAvatar(name: contributorName, imageURL: visit.addedByPhotoURL, size: 16)

                    Text("Visited by \(contributorName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Visited by \(contributorName)")
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

            if !visit.localPhotoNames.isEmpty {
                VisitPhotoStrip(photoNames: visit.localPhotoNames, size: 52)
            } else if !visit.photoNames.isEmpty {
                // Photo files live on the device that logged the visit.
                Label("\(visit.photoNames.count) photo\(visit.photoNames.count == 1 ? "" : "s") on your partner's device", systemImage: "photo.on.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
