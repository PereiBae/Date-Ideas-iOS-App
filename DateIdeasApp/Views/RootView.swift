import AuthenticationServices
import CryptoKit
import PhotosUI
import MapKit
import SwiftUI
import UIKit
import Vision

struct RootView: View {
    @EnvironmentObject private var store: DateIdeaStore
    @EnvironmentObject private var collaborationStore: CollaborationStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var clipboardHasLink = false
    @State private var lastHandledChangeCount = -1
    @State private var queuedShareCount = 0
    @State private var viewingIdea: DateIdea?

    var body: some View {
        TabView {
            Tab("Saved", systemImage: "bookmark") {
                SavedTabView()
            }

            Tab("Map", systemImage: "map") {
                PlacesMapView()
            }

            Tab("Deals", systemImage: "tag") {
                DealAlertsView()
            }
            .badge(store.dealAlertIdeas.count)

            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                SearchView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: store.saveConfirmation != nil || queuedShareCount > 0 || clipboardHasLink) {
            if let confirmation = store.saveConfirmation {
                SaveToastAccessory(workbookName: collaborationStore.activeWorkbook?.name) {
                    if let idea = store.ideas.first(where: { $0.id == confirmation.ideaID }) {
                        viewingIdea = idea
                    }
                    store.saveConfirmation = nil
                } onDismiss: {
                    store.saveConfirmation = nil
                }
            } else if queuedShareCount > 0 {
                SharedQueueAccessory(count: queuedShareCount) {
                    Task {
                        await store.importQueuedShareIfNeeded()
                        refreshImportSignals()
                    }
                }
            } else if clipboardHasLink {
                ClipboardImportAccessory { strings in
                    handlePastedStrings(strings)
                } onDismiss: {
                    lastHandledChangeCount = UIPasteboard.general.changeCount
                    clipboardHasLink = false
                }
            }
        }
        .sheet(isPresented: importSessionPresented) {
            ImportSessionSheet()
        }
        .sheet(item: $viewingIdea) { idea in
            NavigationStack {
                IdeaDetailView(idea: idea)
            }
        }
        .sensoryFeedback(.success, trigger: store.saveConfirmation) { _, newValue in
            newValue != nil
        }
        .task(id: store.saveConfirmation?.id) {
            guard let confirmation = store.saveConfirmation else { return }
            AccessibilityNotification.Announcement("Saved \(confirmation.ideaTitle)").post()
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled, store.saveConfirmation?.id == confirmation.id {
                store.saveConfirmation = nil
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshImportSignals()
            }
        }
        .onChange(of: store.pendingDraft) { _, newDraft in
            if newDraft == nil {
                refreshImportSignals()
            }
        }
        .task {
            refreshImportSignals()
        }
    }

    private var importSessionPresented: Binding<Bool> {
        Binding(
            get: { store.importStage != nil || store.pendingDraft != nil },
            set: { isPresented in
                if !isPresented {
                    store.cancelImport()
                }
            }
        )
    }

    private func refreshImportSignals() {
        queuedShareCount = SharedImportQueue.pendingCount()

        let pasteboard = UIPasteboard.general
        guard pasteboard.changeCount != lastHandledChangeCount else {
            clipboardHasLink = false
            return
        }

        if pasteboard.hasURLs {
            clipboardHasLink = true
        } else if pasteboard.hasStrings {
            let observedChangeCount = pasteboard.changeCount
            Task { @MainActor in
                let patterns = try? await pasteboard.detectedPatterns(for: [\.probableWebURL])
                guard UIPasteboard.general.changeCount == observedChangeCount else { return }
                clipboardHasLink = patterns?.contains(\.probableWebURL) == true
            }
        } else {
            clipboardHasLink = false
        }
    }

    private func handlePastedStrings(_ strings: [String]) {
        lastHandledChangeCount = UIPasteboard.general.changeCount
        clipboardHasLink = false

        guard let value = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }

        Task {
            await store.importLink(value)
        }
    }
}

struct SaveToastAccessory: View {
    let workbookName: String?
    let onView: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text(workbookName.map { "Saved to \($0)" } ?? "Saved")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            Button("View", action: onView)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
    }
}

struct ClipboardImportAccessory: View {
    let onPaste: ([String]) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
                .foregroundStyle(Color.accentColor)

            Text("Link copied")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            PasteButton(payloadType: String.self, onPaste: onPaste)
                .labelStyle(.titleOnly)
                .buttonBorderShape(.capsule)
                .controlSize(.small)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
    }
}

struct SharedQueueAccessory: View {
    let count: Int
    let onImport: () -> Void

    var body: some View {
        Button(action: onImport) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down")
                    .foregroundStyle(Color.accentColor)

                Text(count == 1 ? "1 shared link ready" : "\(count) shared links ready")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("Import")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
    }
}

struct SavedTabView: View {
    @EnvironmentObject private var store: DateIdeaStore
    @EnvironmentObject private var collaborationStore: CollaborationStore
    @State private var importURL = ""
    @State private var importText = ""
    @State private var showingImportField = false
    @State private var showingAccount = false
    @State private var showingWorkbooks = false

    var body: some View {
        NavigationStack {
            IdeaListView()
                .navigationTitle(collaborationStore.activeWorkbook?.name ?? "Saved")
                .toolbarTitleMenu {
                    workbookMenuItems
                }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button {
                            showingAccount = true
                        } label: {
                            Label("Account", systemImage: collaborationStore.currentUser == nil ? "person.crop.circle" : "person.crop.circle.fill")
                        }

                        Menu {
                            workbookMenuItems
                        } label: {
                            Label("Workbooks", systemImage: "books.vertical")
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingImportField = true
                        } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                        }
                    }
                }
                .sheet(isPresented: $showingAccount) {
                    AccountWorkbookView()
                        .environmentObject(collaborationStore)
                }
                .sheet(isPresented: $showingWorkbooks) {
                    NavigationStack {
                        WorkbooksView()
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") {
                                        showingWorkbooks = false
                                    }
                                }
                            }
                    }
                    .environmentObject(store)
                    .environmentObject(collaborationStore)
                }
                .sheet(isPresented: $showingImportField) {
                    ImportLinkView(importURL: $importURL, importText: $importText) {
                        showingImportField = false
                        Task {
                            await store.importLink(importURL, supplementalText: importText)
                            importURL = ""
                            importText = ""
                        }
                    }
                    .presentationDetents([.large])
                }
        }
    }

    @ViewBuilder
    private var workbookMenuItems: some View {
        ForEach(collaborationStore.workbooks) { workbook in
            Button {
                collaborationStore.selectWorkbook(workbook)
            } label: {
                if workbook.id == collaborationStore.activeWorkbook?.id {
                    Label(workbook.name, systemImage: "checkmark")
                } else {
                    Label(workbook.name, systemImage: workbook.isPersonal ? "lock" : "person.2")
                }
            }
        }

        Divider()

        Button {
            showingWorkbooks = true
        } label: {
            Label("Manage workbooks", systemImage: "folder")
        }
    }
}

struct SearchView: View {
    @EnvironmentObject private var store: DateIdeaStore
    @State private var searchText = ""

    private var results: [DateIdea] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        return store.ideas.filter { idea in
            idea.title.localizedCaseInsensitiveContains(query) ||
            idea.location.name.localizedCaseInsensitiveContains(query) ||
            idea.location.address.localizedCaseInsensitiveContains(query) ||
            idea.factualSummary.localizedCaseInsensitiveContains(query) ||
            idea.category.rawValue.localizedCaseInsensitiveContains(query) ||
            idea.displayTagTitles.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "Search your places",
                        systemImage: "magnifyingglass",
                        description: Text("Find places by name, cuisine, dish, or address.")
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List(results) { idea in
                        NavigationLink(value: idea.id) {
                            IdeaRowView(idea: idea)
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .navigationDestination(for: UUID.self) { ideaID in
                if let idea = store.ideas.first(where: { $0.id == ideaID }) {
                    IdeaDetailView(idea: idea)
                } else {
                    ContentUnavailableView("Date idea deleted", systemImage: "trash")
                }
            }
            .searchable(text: $searchText, prompt: "Places, cuisines, dishes")
        }
    }
}

struct AuthenticationGateView: View {
    private enum Mode {
        case signIn
        case createAccount
    }

    @EnvironmentObject private var collaborationStore: CollaborationStore
    @State private var mode = Mode.signIn
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                brandHeader
                    .padding(.top, 48)
                    .padding(.bottom, 36)

                VStack(spacing: 12) {
                    if !collaborationStore.canUseFirebase {
                        unavailableBanner
                    }

                    AppleSignInButton()
                        .environmentObject(collaborationStore)

                    labeledDivider

                    if mode == .createAccount {
                        TextField("Your name", text: $displayName)
                            .textContentType(.name)
                            .modifier(AuthFieldStyle())
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    TextField("name@icloud.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .modifier(AuthFieldStyle())

                    SecureField("Password", text: $password)
                        .textContentType(mode == .createAccount ? .newPassword : .password)
                        .modifier(AuthFieldStyle())

                    Button(action: submit) {
                        Group {
                            if collaborationStore.isSyncing {
                                ProgressView()
                            } else {
                                Text(mode == .signIn ? "Sign in" : "Create account")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(!canSubmit)
                    .padding(.top, 4)

                    if let errorMessage = collaborationStore.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        withAnimation(.smooth(duration: 0.25)) {
                            mode = mode == .signIn ? .createAccount : .signIn
                        }
                        collaborationStore.errorMessage = nil
                    } label: {
                        Text(mode == .signIn ? "New here? Create an account" : "Have an account? Sign in")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)

                Label("Your saved places stay private to your workbooks", systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 28)
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
    }

    private var brandHeader: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                brandCard(color: .teal, symbol: "fork.knife", rotation: -8, offsetY: 6)
                brandCard(color: .orange, symbol: "heart.fill", rotation: 0, offsetY: -6)
                brandCard(color: .blue, symbol: "mappin.and.ellipse", rotation: 8, offsetY: 6)
            }
            .accessibilityHidden(true)

            Text("Date Ideas")
                .font(.system(.largeTitle, design: .serif).weight(.bold))

            Text("Save the places you find, plan them together.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func brandCard(color: Color, symbol: String, rotation: Double, offsetY: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(color.gradient)

            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 62, height: 82)
        .rotationEffect(.degrees(rotation))
        .offset(y: offsetY)
    }

    private var labeledDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5)

            Text("or use email")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize()

            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5)
        }
        .padding(.vertical, 6)
    }

    private var unavailableBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text("Sign-in is temporarily unavailable")
                    .font(.subheadline.weight(.semibold))

                Text(setupHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var setupHint: String {
        if collaborationStore.isFirebaseSDKLinked {
            "Add GoogleService-Info.plist to the app target, then rebuild."
        } else {
            "Add FirebaseAuth and FirebaseFirestore with Swift Package Manager."
        }
    }

    private var canSubmit: Bool {
        guard collaborationStore.canUseFirebase, !collaborationStore.isSyncing else { return false }
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else { return false }

        if mode == .createAccount {
            return !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private func submit() {
        Task {
            collaborationStore.errorMessage = nil

            switch mode {
            case .signIn:
                await collaborationStore.signIn(email: email, password: password)
            case .createAccount:
                await collaborationStore.createAccount(
                    email: email,
                    password: password,
                    displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }
    }
}

private struct AuthFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            }
    }
}

struct AccountWorkbookView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DateIdeaStore
    @EnvironmentObject private var collaborationStore: CollaborationStore
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Firebase") {
                    HStack {
                        Image(systemName: collaborationStore.canUseFirebase ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(collaborationStore.canUseFirebase ? .green : .orange)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(firebaseStatusTitle)
                                .font(.subheadline.weight(.semibold))
                            Text(firebaseStatusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let user = collaborationStore.currentUser {
                    signedInSections(user: user)
                } else {
                    signInSections
                }

                if let errorMessage = collaborationStore.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var firebaseStatusTitle: String {
        if collaborationStore.canUseFirebase {
            "Firebase ready"
        } else if collaborationStore.isFirebaseSDKLinked {
            "Firebase plist needed"
        } else {
            "Firebase SDK needed"
        }
    }

    private var firebaseStatusMessage: String {
        if collaborationStore.canUseFirebase {
            collaborationStore.statusMessage ?? "Auth and Firestore are available."
        } else if collaborationStore.isFirebaseSDKLinked {
            "Add GoogleService-Info.plist to the app target, then rebuild."
        } else {
            "Add FirebaseAuth and FirebaseFirestore with Swift Package Manager."
        }
    }

    private var signInSections: some View {
        Group {
            Section {
                AppleSignInButton()
                    .environmentObject(collaborationStore)
            }

            Section("Sign in") {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()

                SecureField("Password", text: $password)
                    .textContentType(.password)

                Button {
                    Task {
                        await collaborationStore.signIn(email: email, password: password)
                    }
                } label: {
                    Label("Sign In", systemImage: "person.crop.circle.badge.checkmark")
                }
                .disabled(!collaborationStore.canUseFirebase || email.isEmpty || password.isEmpty || collaborationStore.isSyncing)
            }

            Section("Create account") {
                TextField("Display name", text: $displayName)
                    .textContentType(.name)

                Button {
                    Task {
                        await collaborationStore.createAccount(email: email, password: password, displayName: displayName)
                    }
                } label: {
                    Label("Create Account", systemImage: "person.crop.circle.badge.plus")
                }
                .disabled(!collaborationStore.canUseFirebase || email.isEmpty || password.isEmpty || collaborationStore.isSyncing)
            }
        }
    }

    @ViewBuilder
    private func signedInSections(user: AppUser) -> some View {
        Section("Signed in") {
            HStack {
                ContributorAvatar(name: user.displayName, imageURL: user.photoURL)
                VStack(alignment: .leading) {
                    Text(user.displayName)
                    if let email = user.email {
                        Text(email)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button(role: .destructive) {
                Task {
                    await collaborationStore.signOut()
                }
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }

        Section {
            NavigationLink {
                WorkbooksView()
                    .environmentObject(store)
                    .environmentObject(collaborationStore)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Workbooks")

                    if let activeWorkbook = collaborationStore.activeWorkbook {
                        Text("Active: \(activeWorkbook.name)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Setting up your personal workbook")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct AppleSignInButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var collaborationStore: CollaborationStore
    @State private var currentNonce: String?

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            let nonce = Self.randomNonceString()
            currentNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                handleAuthorization(authorization)
            case .failure(let error):
                collaborationStore.errorMessage = "Could not sign in with Apple. \(error.localizedDescription)"
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 48)
        .disabled(!collaborationStore.canUseFirebase || collaborationStore.isSyncing)
        .accessibilityLabel("Sign in with Apple")
    }

    private func handleAuthorization(_ authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            collaborationStore.errorMessage = "Could not read the Apple ID credential."
            return
        }

        guard let nonce = currentNonce else {
            collaborationStore.errorMessage = "Apple sign-in could not be completed. Please try again."
            return
        }

        guard let identityToken = appleIDCredential.identityToken,
              let idToken = String(data: identityToken, encoding: .utf8) else {
            collaborationStore.errorMessage = "Could not read the Apple identity token."
            return
        }

        Task {
            await collaborationStore.signInWithApple(
                idToken: idToken,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )
        }
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var randomBytes = [UInt8](repeating: 0, count: length)
        let result = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)

        guard result == errSecSuccess else {
            fatalError("Unable to generate nonce.")
        }

        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }
}

struct ContributorAvatar: View {
    let name: String
    let imageURL: URL?

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.16))

            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        initialsText
                    }
                }
            } else {
                initialsText
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .accessibilityLabel(name)
    }

    // The frame stays fixed, so initials scale down at accessibility type sizes.
    private var initialsText: some View {
        Text(initials)
            .font(.caption.weight(.bold))
            .minimumScaleFactor(0.6)
            .foregroundStyle(Color.accentColor)
    }
}

struct DealAlertsView: View {
    @EnvironmentObject private var store: DateIdeaStore

    var body: some View {
        NavigationStack {
            List {
                if store.dealAlertIdeas.isEmpty {
                    ContentUnavailableView("No deal alerts", systemImage: "tag", description: Text("Deals ending soon or needing confirmation will appear here."))
                } else {
                    ForEach(store.dealAlertIdeas) { idea in
                        NavigationLink(value: idea.id) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(idea.title)
                                    .font(.headline)

                                ForEach(alertDeals(for: idea)) { deal in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(deal.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text(deal.details)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                        DealStatusLine(deal: deal)
                                    }
                                    .padding(.top, 2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Deals")
            .navigationDestination(for: UUID.self) { ideaID in
                if let idea = store.ideas.first(where: { $0.id == ideaID }) {
                    IdeaDetailView(idea: idea)
                } else {
                    ContentUnavailableView("Date idea deleted", systemImage: "trash")
                }
            }
        }
    }

    private func alertDeals(for idea: DateIdea) -> [Deal] {
        idea.activeDeals.filter { $0.isEndingSoon || $0.status == .needsConfirmation }
    }
}

struct PlacesMapView: View {
    @EnvironmentObject private var store: DateIdeaStore
    @State private var position: MapCameraPosition = .automatic
    @State private var visitFilter = MapVisitFilter.all
    @State private var selectedCategory: IdeaCategory?

    private var mappedIdeas: [DateIdea] {
        store.ideas.filter { idea in
            let hasCoordinate = idea.location.latitude != nil && idea.location.longitude != nil
            let visitMatches = visitFilter.matches(idea)
            let categoryMatches = selectedCategory.map { idea.category == $0 } ?? true
            return hasCoordinate && visitMatches && categoryMatches
        }
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                ForEach(mappedIdeas) { idea in
                    if let coordinate = idea.mapCoordinate {
                        Annotation(idea.title, coordinate: coordinate) {
                            NavigationLink(value: idea.id) {
                                WorkbookMapPin(isVisited: idea.hasVisited)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .safeAreaInset(edge: .top) {
                MapFilterBar(visitFilter: $visitFilter, selectedCategory: $selectedCategory)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { ideaID in
                if let idea = store.ideas.first(where: { $0.id == ideaID }) {
                    IdeaDetailView(idea: idea)
                } else {
                    ContentUnavailableView("Date idea deleted", systemImage: "trash")
                }
            }
        }
    }
}

enum MapVisitFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case wantToGo = "Want to go"
    case visited = "Visited"

    var id: String { rawValue }

    func matches(_ idea: DateIdea) -> Bool {
        switch self {
        case .all:
            return true
        case .wantToGo:
            return !idea.hasVisited
        case .visited:
            return idea.hasVisited
        }
    }
}

struct MapFilterBar: View {
    @Binding var visitFilter: MapVisitFilter
    @Binding var selectedCategory: IdeaCategory?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MapVisitFilter.allCases) { filter in
                        FilterChip(title: filter.rawValue, isSelected: visitFilter == filter) {
                            visitFilter = filter
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "All types", isSelected: selectedCategory == nil) {
                        selectedCategory = nil
                    }

                    ForEach(IdeaCategory.allCases) { category in
                        FilterChip(title: category.rawValue, isSelected: selectedCategory == category) {
                            selectedCategory = category
                        }
                    }
                }
            }
        }
    }
}

struct WorkbookMapPin: View {
    let isVisited: Bool

    private var pinColor: Color {
        isVisited ? .green : .orange
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(.background)
                .frame(width: 38, height: 38)
                .shadow(color: .black.opacity(0.22), radius: 5, y: 3)

            Circle()
                .fill(pinColor)
                .frame(width: 30, height: 30)

            Image(systemName: isVisited ? "checkmark" : "heart.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
        }
        .accessibilityLabel(isVisited ? "Visited place" : "Want to go")
    }
}

private extension DateIdea {
    var mapCoordinate: CLLocationCoordinate2D? {
        guard let latitude = location.latitude, let longitude = location.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct ImportLinkView: View {
    @Binding var importURL: String
    @Binding var importText: String
    @State private var selectedScreenshots: [PhotosPickerItem] = []
    @State private var isReadingScreenshots = false
    @State private var screenshotError: String?

    let onImport: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    TextField("TikTok or Instagram link", text: $importURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }

                Section("Screenshots") {
                    PhotosPicker(selection: $selectedScreenshots, maxSelectionCount: 6, matching: .images) {
                        Label(selectedScreenshots.isEmpty ? "Select caption screenshots" : "\(selectedScreenshots.count) screenshots selected", systemImage: "text.viewfinder")
                    }

                    Button {
                        Task {
                            await appendTextFromScreenshots()
                        }
                    } label: {
                        if isReadingScreenshots {
                            ProgressView()
                        } else {
                            Label("Read Text From Screenshots", systemImage: "doc.text.viewfinder")
                        }
                    }
                    .disabled(selectedScreenshots.isEmpty || isReadingScreenshots)

                    if let screenshotError {
                        Text(screenshotError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("Caption or comments") {
                    TextField("Paste the caption, top comment, address, deal text, or screenshot text", text: $importText, axis: .vertical)
                        .lineLimit(6...12)
                        .textInputAutocapitalization(.sentences)
                }
            }
            .navigationTitle("Import Link")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review") {
                        onImport()
                    }
                    .disabled(importURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @MainActor
    private func appendTextFromScreenshots() async {
        isReadingScreenshots = true
        screenshotError = nil
        defer { isReadingScreenshots = false }

        var recognizedText: [String] = []

        for item in selectedScreenshots {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let text = await ScreenshotTextRecognizer.recognizeText(in: data)
            if !text.isEmpty {
                recognizedText.append(text)
            }
        }

        guard !recognizedText.isEmpty else {
            screenshotError = "No readable text was found in those screenshots."
            return
        }

        let combinedText = recognizedText.joined(separator: "\n\n")
        importText = importText.isEmpty ? combinedText : "\(importText)\n\n\(combinedText)"
        selectedScreenshots = []
    }
}

private enum ScreenshotTextRecognizer {
    static func recognizeText(in data: Data) async -> String {
        await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data)?.cgImage else { return "" }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try? handler.perform([request])

            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }
}
