import SwiftUI
import UIKit

struct IdeaListView: View {
    @EnvironmentObject private var store: DateIdeaStore
    @State private var showingFilters = false

    var body: some View {
        let visibleIdeas = store.filteredIdeas

        List {
            Section {
                filterBar
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                if visibleIdeas.isEmpty && store.filter.isActive {
                    ContentUnavailableView {
                        Label("No matches", systemImage: "line.3.horizontal.decrease")
                    } description: {
                        Text("No saved places match these filters.")
                    } actions: {
                        Button("Clear filters") {
                            store.filter = IdeaFilter()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    // Floating white cards on the paper background.
                    ForEach(visibleIdeas) { idea in
                        NavigationLink(value: idea.id) {
                            IdeaRowView(idea: idea)
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 14, leading: 28, bottom: 14, trailing: 24))
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Theme.cardBackground)
                                .shadow(color: Theme.cardShadow, radius: 16, y: 8)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 5)
                        )
                    }
                    .onDelete { offsets in
                        store.deleteIdeas(at: offsets, from: visibleIdeas)
                    }
                }
            }
        }
        .listStyle(.plain)
        .themedScreenBackground()
        .sheet(isPresented: $showingFilters) {
            FilterSheetView(filter: store.filter, sortOrder: store.sortOrder)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .navigationDestination(for: UUID.self) { ideaID in
            if let idea = store.ideas.first(where: { $0.id == ideaID }) {
                IdeaDetailView(idea: idea)
            } else {
                ContentUnavailableView("Date idea deleted", systemImage: "trash")
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    showingFilters = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.ui(.subheadline, weight: .semibold))

                        Text("Filters")
                            .font(.ui(.subheadline, weight: .semibold))

                        if store.filter.activeCount > 0 {
                            Text("\(store.filter.activeCount)")
                                .font(.ui(.caption2, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.white, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.filter.activeCount > 0 ? "Filters, \(store.filter.activeCount) active" : "Filters")

                if store.sortOrder != .dateAdded {
                    ActiveFilterChip(title: store.sortOrder.rawValue, systemImage: store.sortOrder.systemImage) {
                        store.sortOrder = .dateAdded
                    }
                }

                if let category = store.filter.category {
                    ActiveFilterChip(title: category.rawValue) {
                        store.filter.category = nil
                    }
                }

                if let cuisine = store.filter.cuisineTag {
                    ActiveFilterChip(title: cuisine) {
                        store.filter.cuisineTag = nil
                    }
                }

                if let food = store.filter.foodTag {
                    ActiveFilterChip(title: food) {
                        store.filter.foodTag = nil
                    }
                }

                if store.filter.visitedOnly {
                    ActiveFilterChip(title: visitedChipTitle) {
                        store.filter.visitedOnly = false
                        store.filter.reviewMetric = nil
                    }
                }
            }
            .padding(.trailing, 12)
        }
    }

    private var visitedChipTitle: String {
        if let metric = store.filter.reviewMetric {
            return "Visited · \(metric.rawValue) ≥ \(store.filter.minimumReviewScore.formatted(.number.precision(.fractionLength(1))))"
        }
        return "Visited"
    }
}

struct ActiveFilterChip: View {
    let title: String
    var systemImage: String?
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.ui(.caption, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Text(title)
                    .font(.ui(.subheadline, weight: .medium))
                    .lineLimit(1)

                Image(systemName: "xmark")
                    .font(.ui(.caption2, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule().fill(Color(.secondarySystemGroupedBackground))
                Capsule().strokeBorder(Color(.separator), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove filter: \(title)")
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ui(.subheadline, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    if isSelected {
                        Capsule().fill(Theme.accent)
                    } else {
                        Capsule().fill(Color(.secondarySystemGroupedBackground))
                        Capsule().strokeBorder(Color(.separator), lineWidth: 0.5)
                    }
                }
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct IdeaRowView: View {
    @EnvironmentObject private var collaborationStore: CollaborationStore
    let idea: DateIdea

    private var showsContributor: Bool {
        collaborationStore.activeWorkbook?.isPersonal == false
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IdeaCoverImage(imageName: idea.imageName, url: idea.imageURL)
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottomTrailing) {
                    if showsContributor, let displayName = idea.createdByDisplayName {
                        ContributorAvatar(name: displayName, imageURL: idea.createdByPhotoURL, size: 26)
                            .background(.background, in: Circle())
                            .padding(4)
                            .accessibilityLabel("Added by \(displayName)")
                    }
                }

            VStack(alignment: .leading, spacing: 8) {
                Text(idea.title)
                    .font(.placeTitle(.headline))
                    .lineLimit(2)

                Text(idea.location.address)
                    .font(.ui(.footnote))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)

                if let countdownText = idea.nextDealCountdownText {
                    Label(countdownText, systemImage: "clock")
                        .font(.ui(.caption, weight: .medium))
                        .foregroundStyle(Theme.endingSoon)
                } else if idea.activeDeals.contains(where: { $0.status == .needsConfirmation }) {
                    Label("Confirm deal", systemImage: "exclamationmark.triangle")
                        .font(.ui(.caption, weight: .medium))
                        .foregroundStyle(Theme.endingSoon)
                }

                HStack(spacing: 5) {
                    ForEach(Array(idea.displayTagTitles.prefix(2).enumerated()), id: \.element) { index, tag in
                        TagPill(title: tag, prominent: index == 0)
                            .lineLimit(1)
                    }

                    TagPill(title: idea.category.rawValue, prominent: false)

                    Spacer(minLength: 0)
                }
            }

            // Status indicators live in one trailing column so the star and
            // visited tick stay aligned.
            VStack(alignment: .trailing, spacing: 8) {
                if let score = idea.latestReview(for: collaborationStore.currentUser?.id)?.overallScore {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.ui(.caption2))
                            .foregroundStyle(Theme.accent)

                        Text(score.formatted(.number.precision(.fractionLength(1))))
                            .font(.ui(.caption, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }

                if idea.hasBeenVisited(by: collaborationStore.currentUser?.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.visited)
                        .accessibilityLabel("Visited")
                }
            }
        }
        .padding(.vertical, 6)
        // Keep the row separator full width instead of starting at the text.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}

struct IdeaCoverImage: View {
    let imageName: String?
    let url: URL?

    var body: some View {
        ZStack {
            if let imageName,
               let fileURL = DateIdeaImageStore.fileURL(for: imageName),
               let image = UIImage(contentsOfFile: fileURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipped()
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
