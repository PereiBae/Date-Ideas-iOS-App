import SwiftUI

struct WorkbooksView: View {
    @EnvironmentObject private var store: DateIdeaStore
    @EnvironmentObject private var collaborationStore: CollaborationStore
    @State private var showingCreate = false
    @State private var showingJoin = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if collaborationStore.workbooks.isEmpty {
                    ContentUnavailableView(
                        "Setting up your workbooks",
                        systemImage: "clock",
                        description: Text("Your personal workbook appears here once syncing finishes.")
                    )
                    .padding(.top, 40)
                }

                ForEach(collaborationStore.workbooks) { workbook in
                    WorkbookCard(
                        workbook: workbook,
                        isActive: workbook.id == collaborationStore.activeWorkbook?.id,
                        ideaCount: workbook.id == collaborationStore.activeWorkbook?.id ? store.ideas.count : nil,
                        currentUser: collaborationStore.currentUser
                    ) {
                        collaborationStore.selectWorkbook(workbook)
                    }
                }

                if let errorMessage = collaborationStore.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Workbooks")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    showingCreate = true
                } label: {
                    Label("Create workbook", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)

                Button {
                    showingJoin = true
                } label: {
                    Label("Join with code", systemImage: "ticket")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showingCreate) {
            CreateWorkbookSheet()
                .environmentObject(collaborationStore)
        }
        .sheet(isPresented: $showingJoin) {
            JoinWorkbookSheet()
                .environmentObject(collaborationStore)
        }
    }
}

struct WorkbookCard: View {
    let workbook: Workbook
    let isActive: Bool
    let ideaCount: Int?
    let currentUser: AppUser?
    let onSelect: () -> Void

    private var subtitle: String {
        var parts: [String] = []
        if workbook.isPersonal {
            parts.append("Private to you")
        } else {
            parts.append("\(workbook.memberIDs.count) member\(workbook.memberIDs.count == 1 ? "" : "s")")
        }
        if let ideaCount {
            parts.append("\(ideaCount) idea\(ideaCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Group {
            if isActive {
                cardContent
            } else {
                Button(action: onSelect) {
                    cardContent
                }
                .buttonStyle(.plain)
            }
        }
        .sensoryFeedback(.selection, trigger: isActive) { _, newValue in
            newValue
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(workbook.name)
                    .font(.placeTitle(.title3))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                Spacer()

                if isActive {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                } else if workbook.isPersonal {
                    Image(systemName: "lock")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Private")
                }
            }

            HStack(spacing: 8) {
                if !workbook.isPersonal {
                    memberAvatars
                }

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if isActive && workbook.isShareable {
                ShareLink(item: "Join my RendezQueue workbook with code \(workbook.inviteCode)") {
                    HStack(spacing: 6) {
                        Text("Invite code")
                            .foregroundStyle(.secondary)

                        Text(workbook.inviteCode)
                            .monospaced()
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        Spacer()

                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isActive ? Color.accentColor : Color(.separator),
                    lineWidth: isActive ? 2 : 0.5
                )
        }
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var memberAvatars: some View {
        HStack(spacing: -8) {
            if let currentUser {
                ContributorAvatar(name: currentUser.displayName, imageURL: currentUser.photoURL)
            }

            let others = max(0, workbook.memberIDs.count - 1)
            if others > 0 {
                Text("+\(others)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color(.tertiarySystemGroupedBackground), in: Circle())
                    .overlay {
                        Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 2)
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(memberAvatarsLabel)
    }

    private var memberAvatarsLabel: String {
        let others = max(0, workbook.memberIDs.count - 1)
        if others == 0 {
            return "You are the only member"
        }
        return "Members: you and \(others) other\(others == 1 ? "" : "s")"
    }
}

struct CreateWorkbookSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var collaborationStore: CollaborationStore
    @State private var name = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Our Dates", text: $name)
                } footer: {
                    Text("A shared space for saved places. Invite someone with the code after it's created.")
                }

                if let errorMessage = collaborationStore.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New workbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            isSubmitting = true
                            collaborationStore.errorMessage = nil
                            await collaborationStore.createWorkbook(named: name.trimmingCharacters(in: .whitespacesAndNewlines))
                            isSubmitting = false
                            if collaborationStore.errorMessage == nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct JoinWorkbookSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var collaborationStore: CollaborationStore
    @State private var inviteCode = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("TX4-9KP", text: $inviteCode)
                        .monospaced()
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Ask for the invite code shown on their workbook.")
                }

                if let errorMessage = collaborationStore.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Join workbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        Task {
                            isSubmitting = true
                            collaborationStore.errorMessage = nil
                            await collaborationStore.joinWorkbook(inviteCode: inviteCode.trimmingCharacters(in: .whitespacesAndNewlines))
                            isSubmitting = false
                            if collaborationStore.errorMessage == nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
