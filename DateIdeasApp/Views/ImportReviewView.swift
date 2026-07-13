import SwiftUI

struct ImportSessionSheet: View {
    @EnvironmentObject private var store: DateIdeaStore
    @EnvironmentObject private var collaborationStore: CollaborationStore

    var body: some View {
        Group {
            if let draft = store.pendingDraft {
                ImportReviewView(draft: draft) { reviewedDraft, targetWorkbook in
                    if let targetWorkbook, targetWorkbook.id != collaborationStore.activeWorkbook?.id {
                        // Saving into a different workbook: write remotely only;
                        // the active workbook's local list is untouched.
                        Task {
                            await collaborationStore.copyIdea(reviewedDraft.extractedIdea, to: targetWorkbook)
                        }
                        store.completeDraftSavedElsewhere(reviewedDraft, workbookName: targetWorkbook.name)
                    } else {
                        store.saveDraft(reviewedDraft)
                    }
                }
            } else {
                ExtractionProgressView(stage: store.importStage ?? .fetchingCaption, preview: store.streamingPreview)
            }
        }
        .animation(.smooth(duration: 0.3), value: store.pendingDraft != nil)
        // Sheets don't reliably inherit the root tint; stamp it explicitly.
        .tint(Theme.accent)
    }
}

struct ExtractionProgressView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let stage: ImportStage
    var preview: ExtractionPreview?
    @State private var shimmering = false

    private var stageIndex: Int {
        switch stage {
        case .fetchingCaption: 0
        case .extracting: 1
        case .resolvingPlace: 2
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    stageRow(index: 0, title: "Fetching the caption")
                    extractingRow
                    stageRow(index: 2, title: "Matching the place on Maps")
                } footer: {
                    extractionFootnote
                }

                Section {
                    skeletonFields
                }
            }
            .navigationTitle("Importing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                shimmering = true
            }
        }
    }

    @ViewBuilder
    private var extractingRow: some View {
        if case .extracting(.appleIntelligence) = stage {
            HStack(spacing: 12) {
                stageIndicator(index: 1)

                Label {
                    Text("Extracting with Apple Intelligence")
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.aiGradient)
                }
            }
        } else if case .extracting(.parser) = stage {
            stageRow(index: 1, title: "Reading details from the caption")
        } else {
            stageRow(index: 1, title: "Extracting the details")
        }
    }

    @ViewBuilder
    private var extractionFootnote: some View {
        switch stage {
        case .extracting(.appleIntelligence):
            Label("Runs on this device. The caption never leaves your iPhone.", systemImage: "lock")
        case .extracting(.parser):
            Text("Apple Intelligence isn't available right now, so the caption is read directly. You can fill in anything missing on the next screen.")
        default:
            EmptyView()
        }
    }

    private func stageRow(index: Int, title: String) -> some View {
        HStack(spacing: 12) {
            stageIndicator(index: index)

            Text(title)
                .foregroundStyle(index <= stageIndex ? .primary : .secondary)
        }
    }

    @ViewBuilder
    private func stageIndicator(index: Int) -> some View {
        if index < stageIndex {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Done")
        } else if index == stageIndex {
            ProgressView()
                .accessibilityLabel("In progress")
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Waiting")
        }
    }

    private var skeletonFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            if preview == nil || preview?.isEmpty == true {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                    .frame(height: 140)
                    .opacity(shimmerOpacity)
                    .accessibilityHidden(true)
            }

            // Fields fill in live as Apple Intelligence streams them.
            streamedField(label: "Name", value: preview?.name, placeholder: "A lovely place somewhere")
            streamedField(label: "Location", value: preview?.address, placeholder: "12 Placeholder Road, Singapore")
            streamedField(label: "Summary", value: preview?.summary, placeholder: "A short factual summary of the place appears here once extraction finishes.")
        }
        .padding(.vertical, 4)
        .animation(.smooth(duration: 0.25), value: preview)
    }

    private var shimmerOpacity: Double {
        reduceMotion ? 0.6 : (shimmering ? 0.4 : 0.9)
    }

    @ViewBuilder
    private func streamedField(label: String, value: String?, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let value, !value.isEmpty {
                Text(value)
                    .font(.body)
                    .contentTransition(.interpolate)
            } else {
                Text(placeholder)
                    .font(.body)
                    .redacted(reason: .placeholder)
                    .opacity(shimmerOpacity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: shimmering)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct ImportReviewView: View {
    private enum AIField: Hashable {
        case title
        case category
        case summary
        case address
        case tags
        case deals
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @EnvironmentObject private var collaborationStore: CollaborationStore
    @State private var draft: ImportDraft
    @State private var aiFields: Set<AIField>
    @State private var keyboardVisible = false
    @State private var selectedWorkbookID: String?

    let onSave: (ImportDraft, Workbook?) -> Void

    init(draft: ImportDraft, onSave: @escaping (ImportDraft, Workbook?) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave

        var fields: Set<AIField> = []
        if draft.extractionMethod == .appleIntelligence {
            let idea = draft.extractedIdea
            fields.insert(.category)
            if !idea.title.isEmpty { fields.insert(.title) }
            if !idea.factualSummary.isEmpty { fields.insert(.summary) }
            if !idea.location.address.isEmpty { fields.insert(.address) }
            if !idea.cuisineTagNames.isEmpty || !idea.foodTagNames.isEmpty { fields.insert(.tags) }
            if !idea.deals.isEmpty { fields.insert(.deals) }
        }
        _aiFields = State(initialValue: fields)
    }

    var body: some View {
        NavigationStack {
            Form {
                heroSection
                detailsSection
                locationSection
                cuisineSection
                foodSection
                dealSection
                sourceSection
                saveTargetSection
            }
            .onAppear {
                if selectedWorkbookID == nil {
                    selectedWorkbookID = collaborationStore.activeWorkbook?.id
                }
            }
            .keyboardDismissal()
            .navigationTitle("Review Import")
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
            .onChange(of: draft.extractedIdea.title) { aiFields.remove(.title) }
            .onChange(of: draft.extractedIdea.category) { aiFields.remove(.category) }
            .onChange(of: draft.extractedIdea.factualSummary) { aiFields.remove(.summary) }
            .onChange(of: draft.extractedIdea.location.address) { aiFields.remove(.address) }
            .onChange(of: draft.extractedIdea.cuisineTagNames) { aiFields.remove(.tags) }
            .onChange(of: draft.extractedIdea.foodTagNames) { aiFields.remove(.tags) }
            .onChange(of: draft.extractedIdea.deals) { aiFields.remove(.deals) }
        }
    }

    // MARK: Sections

    private var heroSection: some View {
        Section {
            IdeaCoverImage(imageName: draft.extractedIdea.imageName, url: draft.extractedIdea.imageURL)
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .topTrailing) {
                    confidenceBadge
                        .padding(10)
                }
                .overlay(alignment: .bottomLeading) {
                    methodBadge
                        .padding(10)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

            TextField("Image URL", text: Binding(
                get: { draft.extractedIdea.imageURL?.absoluteString ?? "" },
                set: { value in
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft.extractedIdea.imageURL = trimmed.isEmpty ? nil : URL(string: trimmed)
                }
            ))
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .font(.footnote)
            .foregroundStyle(.secondary)
        } footer: {
            if let note = draft.extractionNote, !note.isEmpty {
                Text(note)
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            aiMarkedRow(.title) {
                TextField("Name", text: $draft.extractedIdea.title)
                    .font(.placeTitle(.body))
            }

            aiMarkedRow(.category) {
                Picker("Type", selection: $draft.extractedIdea.category) {
                    ForEach(IdeaCategory.allCases) { category in
                        Label(category.rawValue, systemImage: category.systemImage)
                            .tag(category)
                    }
                }
                // Pushed list style: icons on every row, selection tick trailing.
                .pickerStyle(.navigationLink)
            }

            aiMarkedRow(.summary) {
                TextField("Summary", text: $draft.extractedIdea.factualSummary, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
    }

    private var locationSection: some View {
        Section("Location") {
            aiMarkedRow(.address) {
                TextField("Address", text: $draft.extractedIdea.location.address, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
    }

    private var cuisineSection: some View {
        Section {
            EditableTagChips(tags: $draft.extractedIdea.cuisineTagNames, addPrompt: "Add a cuisine (e.g. Korean)")
        } header: {
            sectionHeader("Cuisine", aiField: .tags)
        }
    }

    private var foodSection: some View {
        Section {
            EditableTagChips(tags: $draft.extractedIdea.foodTagNames, addPrompt: "Add a dish or drink (e.g. Ramyun)")
        } header: {
            sectionHeader("Food items", aiField: .tags)
        }
    }

    private var dealSection: some View {
        Section {
            if draft.extractedIdea.deals.isEmpty {
                Button {
                    draft.extractedIdea.deals.append(Deal(title: "", details: "", status: .unknown))
                } label: {
                    Label("Add Deal", systemImage: "tag")
                }
            } else {
                ForEach($draft.extractedIdea.deals) { $deal in
                    DealEditorRows(deal: $deal)
                }
            }
        } header: {
            sectionHeader("Deal", aiField: .deals)
        }
    }

    private var sourceSection: some View {
        Section("Source") {
            Text(draft.platform)

            Text(draft.rawCaption)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if draft.rawCaption.localizedCaseInsensitiveContains("no public caption metadata") {
                Text("This platform did not expose the caption through the shared link. Add screenshots only when this happens.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: Badges & provenance

    // Reduce Transparency swaps the glassy badge background for a solid one.
    private var badgeBackground: AnyShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.thinMaterial)
    }

    private var confidenceBadge: some View {
        Label(
            draft.confidence.formatted(.percent.precision(.fractionLength(0))),
            systemImage: "checkmark.seal"
        )
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(badgeBackground, in: Capsule())
        .accessibilityLabel("Extraction confidence \(draft.confidence.formatted(.percent.precision(.fractionLength(0))))")
    }

    @ViewBuilder
    private var methodBadge: some View {
        if draft.extractionMethod == .appleIntelligence {
            Label("Apple Intelligence", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.aiGradient, in: Capsule())
        } else {
            Label("Parsed from caption", systemImage: "slider.horizontal.3")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(badgeBackground, in: Capsule())
        }
    }

    private func aiMarkedRow<Content: View>(_ field: AIField, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            content()

            if aiFields.contains(field) {
                AIProvenanceMark()
            }
        }
        // Keep row separators full width (Label rows shift them otherwise).
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    private func sectionHeader(_ title: String, aiField: AIField) -> some View {
        HStack(spacing: 6) {
            Text(title)

            if aiFields.contains(aiField) {
                AIProvenanceMark()
            }
        }
    }

    // MARK: Save

    private var selectedWorkbook: Workbook? {
        collaborationStore.workbooks.first { $0.id == selectedWorkbookID }
            ?? collaborationStore.activeWorkbook
    }

    @ViewBuilder
    private var saveTargetSection: some View {
        if collaborationStore.workbooks.count > 1 {
            Section {
                Picker("Workbook", selection: $selectedWorkbookID) {
                    ForEach(collaborationStore.workbooks) { workbook in
                        Label(workbook.name, systemImage: workbook.isPersonal ? "lock" : "person.2")
                            .tag(Optional(workbook.id))
                    }
                }
                .pickerStyle(.navigationLink)
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            } header: {
                Text("Save to")
            }
        }
    }

    private var saveBar: some View {
        Button(action: save) {
            Text(saveButtonTitle)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(draft.extractedIdea.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var saveButtonTitle: String {
        if let workbook = selectedWorkbook {
            "Save to \(workbook.name)"
        } else {
            "Save"
        }
    }

    private func save() {
        draft.extractedIdea.location.name = draft.extractedIdea.title
        onSave(draft, selectedWorkbook)
        dismiss()
    }

}

// Removable tag chips with an inline field to add new free-form tags.
struct EditableTagChips: View {
    @Binding var tags: [String]
    let addPrompt: String
    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            tags.removeAll { $0 == tag }
                        } label: {
                            HStack(spacing: 5) {
                                Text(tag)
                                    .font(.subheadline.weight(.medium))

                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(Theme.accent)
                            .background(Theme.accent.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove tag \(tag)")
                    }
                }
            }

            HStack(spacing: 8) {
                TextField(addPrompt, text: $newTag)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(addTag)

                Button(action: addTag) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add tag")
            }
        }
        .padding(.vertical, 4)
    }

    private func addTag() {
        guard let tag = PlaceTagNormalizer.normalizeSingle(newTag) else {
            newTag = ""
            return
        }

        if !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            tags.append(tag)
        }
        newTag = ""
    }
}

struct AIProvenanceMark: View {
    var body: some View {
        Image(systemName: "sparkle")
            .font(.caption)
            .foregroundStyle(Theme.aiGradient)
            .accessibilityLabel("Filled by Apple Intelligence")
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }

        return CGSize(width: maxWidth.isFinite ? maxWidth : usedWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
