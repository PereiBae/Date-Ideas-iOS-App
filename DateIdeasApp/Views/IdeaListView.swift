import SwiftUI
import UIKit

struct IdeaListView: View {
    @EnvironmentObject private var store: DateIdeaStore

    var body: some View {
        let visibleIdeas = store.filteredIdeas

        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "All types", isSelected: store.selectedCategory == nil) {
                            store.selectedCategory = nil
                        }

                        ForEach(IdeaCategory.allCases) { category in
                            FilterChip(title: category.rawValue, isSelected: store.selectedCategory == category) {
                                store.selectedCategory = category
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "Any cuisine", isSelected: store.selectedCuisineTag == nil) {
                            store.selectedCuisineTag = nil
                        }

                        ForEach(store.availableCuisineTags) { tag in
                            FilterChip(title: tag.rawValue, isSelected: store.selectedCuisineTag == tag) {
                                store.selectedCuisineTag = tag
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "Any food", isSelected: store.selectedFoodTag == nil) {
                            store.selectedFoodTag = nil
                        }

                        ForEach(store.availableFoodTags) { tag in
                            FilterChip(title: tag.rawValue, isSelected: store.selectedFoodTag == tag) {
                                store.selectedFoodTag = tag
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                Toggle("Visited only", isOn: $store.showingVisitedOnly)

                if store.showingVisitedOnly || store.selectedReviewMetric != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                FilterChip(title: "Any rating", isSelected: store.selectedReviewMetric == nil) {
                                    store.selectedReviewMetric = nil
                                }

                                ForEach(ReviewMetric.allCases) { metric in
                                    FilterChip(title: metric.rawValue, isSelected: store.selectedReviewMetric == metric) {
                                        store.selectedReviewMetric = metric
                                        store.showingVisitedOnly = true
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }

                        if store.selectedReviewMetric != nil {
                            Stepper(
                                "Minimum \(store.minimumReviewScore.formatted(.number.precision(.fractionLength(1))))",
                                value: $store.minimumReviewScore,
                                in: 1...5,
                                step: 0.5
                            )
                        }
                    }
                }
            }

            Section {
                ForEach(visibleIdeas) { idea in
                    NavigationLink(value: idea.id) {
                        IdeaRowView(idea: idea)
                    }
                }
                .onDelete { offsets in
                    store.deleteIdeas(at: offsets, from: visibleIdeas)
                }
            }
        }
        .navigationDestination(for: UUID.self) { ideaID in
            if let idea = store.ideas.first(where: { $0.id == ideaID }) {
                IdeaDetailView(idea: idea)
            } else {
                ContentUnavailableView("Date idea deleted", systemImage: "trash")
            }
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    if isSelected {
                        Capsule().fill(Color.accentColor)
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
                        ContributorAvatar(name: displayName, imageURL: idea.createdByPhotoURL)
                            .frame(width: 28, height: 28)
                            .background(.background, in: Circle())
                            .padding(4)
                            .accessibilityLabel("Added by \(displayName)")
                    }
                }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(idea.title)
                        .font(.placeTitle(.headline))
                        .lineLimit(2)

                    Spacer()

                    if let score = idea.latestReview?.overallScore {
                        Label(score.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.yellow)
                    }
                }

                Text(idea.location.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(idea.factualSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let countdownText = idea.nextDealCountdownText {
                    Label(countdownText, systemImage: "clock")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                } else if idea.activeDeals.contains(where: { $0.status == .needsConfirmation }) {
                    Label("Confirm deal", systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }

                HStack {
                    Text(idea.category.rawValue)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(Capsule())

                    ForEach(idea.displayTagTitles.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if idea.hasVisited {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Visited")
                    }
                }
            }
        }
        .padding(.vertical, 6)
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
