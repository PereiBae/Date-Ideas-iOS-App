import SwiftUI

struct FilterSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DateIdeaStore
    @State private var draft: IdeaFilter
    @State private var sortOrder: IdeaSortOrder

    init(filter: IdeaFilter, sortOrder: IdeaSortOrder) {
        _draft = State(initialValue: filter)
        _sortOrder = State(initialValue: sortOrder)
    }

    private var matchCount: Int {
        store.ideas.filter { draft.matches($0, currentUserID: store.currentUserID) }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    sortSection
                    categorySection

                    if !store.availableCuisineTags.isEmpty {
                        cuisineSection
                    }

                    if !store.availableFoodTags.isEmpty {
                        foodSection
                    }

                    visitedSection
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Sort & Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
            .onChange(of: draft.visitedOnly) {
                if !draft.visitedOnly {
                    draft.reviewMetric = nil
                }
            }
        }
        .tint(Theme.accent)
    }

    // MARK: Sections

    private var sortSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Sort by")

            FlowLayout(spacing: 8) {
                ForEach(IdeaSortOrder.allCases) { order in
                    IconFilterChip(
                        title: order.rawValue,
                        systemImage: order.systemImage,
                        isSelected: sortOrder == order
                    ) {
                        sortOrder = order
                        if order == .nearMe {
                            store.requestLocationForSorting()
                        }
                    }
                }
            }

            if sortOrder == .nearMe && store.locationDenied {
                Label("Allow location access in Settings to sort by distance.", systemImage: "location.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Type of place")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 14) {
                ForEach(IdeaCategory.allCases) { category in
                    CategoryTile(category: category, isSelected: draft.category == category) {
                        draft.category = draft.category == category ? nil : category
                    }
                }
            }
        }
    }

    private var cuisineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Cuisine")

            FlowLayout(spacing: 8) {
                ForEach(store.availableCuisineTags, id: \.self) { tag in
                    FilterChip(title: tag, isSelected: draft.cuisineTag == tag) {
                        draft.cuisineTag = draft.cuisineTag == tag ? nil : tag
                    }
                }
            }
        }
    }

    private var foodSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Food")

            FlowLayout(spacing: 8) {
                ForEach(store.availableFoodTags, id: \.self) { tag in
                    FilterChip(title: tag, isSelected: draft.foodTag == tag) {
                        draft.foodTag = draft.foodTag == tag ? nil : tag
                    }
                }
            }
        }
    }

    private var visitedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Visited")

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Visited only", isOn: $draft.visitedOnly)

                if draft.visitedOnly {
                    Divider()

                    FlowLayout(spacing: 8) {
                        FilterChip(title: "Any rating", isSelected: draft.reviewMetric == nil) {
                            draft.reviewMetric = nil
                        }

                        ForEach(ReviewMetric.allCases) { metric in
                            FilterChip(title: metric.rawValue, isSelected: draft.reviewMetric == metric) {
                                draft.reviewMetric = metric
                            }
                        }
                    }

                    if draft.reviewMetric != nil {
                        Stepper(
                            "Minimum \(draft.minimumReviewScore.formatted(.number.precision(.fractionLength(1))))",
                            value: $draft.minimumReviewScore,
                            in: 1...5,
                            step: 0.5
                        )
                    }
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }

    // MARK: Actions

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button("Clear") {
                draft = IdeaFilter()
                sortOrder = .dateAdded
            }
            .buttonStyle(.glass)
            .disabled(!draft.isActive && sortOrder == .dateAdded)

            Button(action: apply) {
                Text(matchCount == 1 ? "Show 1 place" : "Show \(matchCount) places")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func apply() {
        store.filter = draft
        store.sortOrder = sortOrder
        dismiss()
    }
}

struct IconFilterChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(isSelected ? .semibold : .medium))
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

private struct CategoryTile: View {
    let category: IdeaCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    if isSelected {
                        Circle().fill(Theme.accent)
                    } else {
                        Circle().fill(Color(.secondarySystemGroupedBackground))
                        Circle().strokeBorder(Color(.separator), lineWidth: 0.5)
                    }

                    Image(systemName: category.systemImage)
                        .font(.title3)
                        .foregroundStyle(isSelected ? .white : .primary)
                }
                .frame(width: 52, height: 52)

                Text(category.rawValue)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel(category.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
