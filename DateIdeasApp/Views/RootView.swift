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

            Tab("You", systemImage: "person.crop.circle") {
                AccountWorkbookView()
            }

            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                SearchView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: store.saveConfirmation != nil || queuedShareCount > 0 || clipboardHasLink) {
            if let confirmation = store.saveConfirmation {
                SaveToastAccessory(workbookName: confirmation.workbookName ?? collaborationStore.activeWorkbook?.name) {
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
            .tint(Theme.accent)
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
                store.resumeSharedAutoImport()
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
        if queuedShareCount > 0 {
            CaptionExtractorPrewarmer.prewarm()

            // Shared links import themselves; the user only reviews and saves.
            // After each save the next queued link starts automatically.
            if !store.sharedAutoImportPaused, store.pendingDraft == nil, store.importStage == nil {
                Task {
                    await store.importQueuedShareIfNeeded()
                    refreshImportSignals()
                }
            }
        }

        let pasteboard = UIPasteboard.general
        guard pasteboard.changeCount != lastHandledChangeCount else {
            clipboardHasLink = false
            return
        }

        if pasteboard.hasURLs {
            clipboardHasLink = true
            CaptionExtractorPrewarmer.prewarm()
        } else if pasteboard.hasStrings {
            let observedChangeCount = pasteboard.changeCount
            Task { @MainActor in
                let patterns = try? await pasteboard.detectedPatterns(for: [\.probableWebURL])
                guard UIPasteboard.general.changeCount == observedChangeCount else { return }
                clipboardHasLink = patterns?.contains(\.probableWebURL) == true
                if clipboardHasLink {
                    CaptionExtractorPrewarmer.prewarm()
                }
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
                .foregroundStyle(Theme.visited)

            Text(workbookName.map { "Saved to \($0)" } ?? "Saved")
                .font(.ui(.subheadline, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            Button("View", action: onView)
                .font(.ui(.subheadline, weight: .semibold))
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
                .foregroundStyle(Theme.accent)

            Text("Link copied")
                .font(.ui(.subheadline, weight: .medium))
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
                    .foregroundStyle(Theme.accent)

                Text(count == 1 ? "1 shared link ready" : "\(count) shared links ready")
                    .font(.ui(.subheadline, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("Import")
                    .font(.ui(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.accent)
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
    @State private var showingWorkbooks = false
    @State private var showingJoinWorkbook = false

    var body: some View {
        NavigationStack {
            IdeaListView()
                // Import floating action button (mockup design).
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        showingImportField = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: Theme.accent.opacity(0.45), radius: 12, y: 6)
                    }
                    .accessibilityLabel("Import a date idea")
                    .padding(.trailing, 20)
                    .padding(.bottom, 12)
                }
                .navigationTitle(collaborationStore.activeWorkbook?.name ?? "Saved")
                .toolbarTitleMenu {
                    workbookMenuItems
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            workbookMenuItems
                        } label: {
                            Label("Workbooks", systemImage: "books.vertical")
                        }
                    }
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
                    .tint(Theme.accent)
                    .environmentObject(store)
                    .environmentObject(collaborationStore)
                }
                .sheet(isPresented: $showingJoinWorkbook) {
                    JoinWorkbookSheet()
                        .tint(Theme.accent)
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
                    .tint(Theme.accent)
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
            showingJoinWorkbook = true
        } label: {
            Label("Join with invite code", systemImage: "ticket")
        }

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
            .themedScreenBackground()
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

                    GoogleSignInButton()
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
                    .buttonStyle(.plain)
                    .font(.ui(.body, weight: .bold))
                    .foregroundStyle(Color(light: 0x7A3418, dark: 0x7A3418))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .opacity(canSubmit ? 1 : 0.55)
                    .disabled(!canSubmit)
                    .padding(.top, 4)

                    if let errorMessage = collaborationStore.errorMessage {
                        Text(errorMessage)
                            .font(.ui(.footnote))
                            .foregroundStyle(Color(light: 0xFFE3DC, dark: 0xFFE3DC))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        withAnimation(.smooth(duration: 0.25)) {
                            mode = mode == .signIn ? .createAccount : .signIn
                        }
                        collaborationStore.errorMessage = nil
                    } label: {
                        Text(mode == .signIn ? "New here? Create an account" : "Have an account? Sign in")
                            .font(.ui(.subheadline, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)

                Label("Your saved places stay private to your workbooks", systemImage: "lock")
                    .font(.ui(.footnote))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 28)
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(
                colors: [Color(light: 0xC25A2A, dark: 0xA34A20), Color(light: 0x7A3418, dark: 0x5E2812)],
                startPoint: .topLeading,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .environment(\.colorScheme, .dark)
        .scrollDismissesKeyboard(.interactively)
    }

    private var brandHeader: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                brandCard(color: Color(light: 0xF58A3C, dark: 0xF58A3C), symbol: "fork.knife", rotation: -8, offsetY: 6)
                brandCard(color: Color(light: 0xE86FA0, dark: 0xE86FA0), symbol: "heart.fill", rotation: 0, offsetY: -6)
                brandCard(color: Color(light: 0xE8551A, dark: 0xE8551A), symbol: "mappin.and.ellipse", rotation: 8, offsetY: 6)
            }
            .accessibilityHidden(true)

            Text("RendezQueue")
                .font(.displayHeavy(.largeTitle))
                .foregroundStyle(.white)

            Text("Your next date, already saved.")
                .font(.ui(.subheadline))
                .foregroundStyle(.white.opacity(0.8))
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
                .font(.ui(.footnote))
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
                    .font(.ui(.subheadline, weight: .semibold))

                Text(setupHint)
                    .font(.ui(.footnote))
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
            .foregroundStyle(.white)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
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
                if !collaborationStore.canUseFirebase {
                    Section {
                        Label("Sign-in is temporarily unavailable. Please try again later.", systemImage: "exclamationmark.triangle.fill")
                            .font(.ui(.footnote))
                            .foregroundStyle(.secondary)
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
                            .font(.ui(.footnote))
                            .foregroundStyle(.red)
                    }
                }
            }
            .themedScreenBackground()
            .navigationTitle("You")
        }
    }

    private var signInSections: some View {
        Group {
            Section {
                AppleSignInButton()
                    .environmentObject(collaborationStore)

                GoogleSignInButton()
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
                            .font(.ui(.footnote))
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
                            .font(.ui(.footnote))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Setting up your personal workbook")
                            .font(.ui(.footnote))
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

struct GoogleSignInButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var collaborationStore: CollaborationStore

    var body: some View {
        Button {
            Task {
                await collaborationStore.signInWithGoogle()
            }
        } label: {
            HStack(spacing: 10) {
                GoogleLogoMark()
                    .frame(width: 20, height: 20)

                Text("Continue with Google")
                    .font(.system(size: 18, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(textColor)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .disabled(!collaborationStore.canUseFirebase || collaborationStore.isSyncing)
        .accessibilityLabel("Continue with Google")
    }

    // Chrome colors from Google's sign-in branding guidelines.
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.075, green: 0.075, blue: 0.078) : .white
    }

    private var textColor: Color {
        colorScheme == .dark ? Color(red: 0.89, green: 0.89, blue: 0.89) : Color(red: 0.12, green: 0.12, blue: 0.12)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color(red: 0.56, green: 0.57, blue: 0.56) : Color(red: 0.45, green: 0.46, blue: 0.46)
    }
}

// The Google "G" drawn from arc segments, so no image asset is needed.
struct GoogleLogoMark: View {
    private static let blue = Color(red: 0.259, green: 0.522, blue: 0.957)
    private static let green = Color(red: 0.204, green: 0.659, blue: 0.325)
    private static let yellow = Color(red: 0.984, green: 0.737, blue: 0.02)
    private static let red = Color(red: 0.918, green: 0.263, blue: 0.208)

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let ring = size * 0.2

            ZStack {
                segment(from: 0.0, to: 0.125, color: Self.blue, ring: ring)
                segment(from: 0.125, to: 0.375, color: Self.green, ring: ring)
                segment(from: 0.375, to: 0.625, color: Self.yellow, ring: ring)
                segment(from: 0.625, to: 0.875, color: Self.red, ring: ring)

                Rectangle()
                    .fill(Self.blue)
                    .frame(width: size / 2, height: ring)
                    .position(x: size * 0.75, y: size / 2)
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }

    private func segment(from: CGFloat, to: CGFloat, color: Color, ring: CGFloat) -> some View {
        Circle()
            .inset(by: ring / 2)
            .trim(from: from, to: to)
            .stroke(color, lineWidth: ring)
    }
}

struct ContributorAvatar: View {
    let name: String
    let imageURL: URL?
    // Size is a real parameter: wrapping the avatar in a smaller outer frame
    // makes the image overflow its slot and look misaligned.
    var size: CGFloat = 32

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.avatarGradient)

            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                    default:
                        initialsText
                    }
                }
            } else {
                initialsText
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(name)
    }

    // The frame stays fixed, so initials scale down at accessibility type sizes.
    private var initialsText: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .bold))
            .minimumScaleFactor(0.6)
            .foregroundStyle(.white)
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
                                    .font(.ui(.headline, weight: .semibold))

                                ForEach(alertDeals(for: idea)) { deal in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(deal.title)
                                            .font(.ui(.subheadline, weight: .semibold))
                                        Text(deal.details)
                                            .font(.ui(.footnote))
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
            .themedScreenBackground()
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
    @State private var selectedIdeaID: UUID?
    @State private var showingCategoryPicker = false
    @State private var isSearching = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    private var mappedIdeas: [DateIdea] {
        store.ideas.filter { idea in
            let hasCoordinate = idea.location.latitude != nil && idea.location.longitude != nil
            let visitMatches = visitFilter.matches(idea, currentUserID: store.currentUserID)
            let categoryMatches = selectedCategory.map { idea.category == $0 } ?? true
            return hasCoordinate && visitMatches && categoryMatches
        }
    }

    private var selectedIdea: DateIdea? {
        mappedIdeas.first { $0.id == selectedIdeaID }
    }

    // Only offer types that actually have a mappable saved place.
    private var availableCategories: [IdeaCategory] {
        IdeaCategory.allCases.filter { category in
            store.ideas.contains { idea in
                idea.category == category && idea.location.latitude != nil && idea.location.longitude != nil
            }
        }
    }

    private var isFilterActive: Bool {
        visitFilter != .all || selectedCategory != nil
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                // The blue current-location dot; appears once location is granted.
                UserAnnotation()

                ForEach(mappedIdeas) { idea in
                    if let coordinate = idea.mapCoordinate {
                        Annotation(idea.title, coordinate: coordinate) {
                            Button {
                                withAnimation(.smooth(duration: 0.25)) {
                                    selectedIdeaID = selectedIdeaID == idea.id ? nil : idea.id
                                }
                            } label: {
                                WorkbookMapPin(
                                    isVisited: idea.hasBeenVisited(by: store.currentUserID),
                                    isSelected: idea.id == selectedIdeaID
                                )
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
            // MapKit elements (user-location dot, location button) stay system
            // blue; our overlays are added after this so they keep the rosé tint.
            .tint(.blue)
            .overlay {
                if showingCategoryPicker {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.smooth(duration: 0.25)) {
                                showingCategoryPicker = false
                            }
                        }
                        .accessibilityLabel("Close type filter")
                }
            }
            .overlay(alignment: .topTrailing) {
                if showingCategoryPicker {
                    VStack(alignment: .trailing, spacing: 8) {
                        categoryRow(title: "All types", systemImage: "mappin.and.ellipse", isSelected: selectedCategory == nil) {
                            selectCategory(nil)
                        }

                        ForEach(availableCategories) { category in
                            categoryRow(title: category.rawValue, systemImage: category.systemImage, isSelected: selectedCategory == category) {
                                selectCategory(category)
                            }
                        }
                    }
                    .padding(.trailing)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .overlay(alignment: .bottomLeading) {
                if isFilterActive && selectedIdea == nil && !showingCategoryPicker {
                    Text(countText)
                        .font(.ui(.footnote, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.leading)
                        .padding(.bottom, 10)
                }
            }
            .overlay(alignment: .bottom) {
                if let idea = selectedIdea, !showingCategoryPicker {
                    MapPreviewCard(idea: idea, distanceText: distanceText(for: idea)) {
                        withAnimation(.smooth(duration: 0.25)) {
                            selectedIdeaID = nil
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) {
                if isSearching {
                    searchResultsPanel
                        .padding(.horizontal)
                        .padding(.top, 6)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                headerBar
            }
            // The search keyboard must not resize the map: animating the map's
            // frame churns MapKit's Metal drawable and crashes (same failure as
            // the old expanding header).
            .ignoresSafeArea(.keyboard)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { ideaID in
                if let idea = store.ideas.first(where: { $0.id == ideaID }) {
                    IdeaDetailView(idea: idea)
                } else {
                    ContentUnavailableView("Date idea deleted", systemImage: "trash")
                }
            }
            .onChange(of: visitFilter) { dropSelectionIfHidden() }
            .onChange(of: selectedCategory) { dropSelectionIfHidden() }
            // Re-assert rosé for everything layered on the map (header, popups,
            // preview card, pushed screens); the inner .tint(.blue) sits closer
            // to the Map so MapKit's own elements stay blue.
            .tint(Theme.accent)
            .task {
                // Opening the map is the contextual moment to ask for location
                // (prompts only while permission is undetermined).
                store.requestLocationForSorting()
            }
        }
    }

    // Frosted bar the map slides underneath. Fixed height: resizing the map
    // (e.g. expanding this bar) churns MapKit's Metal drawable and crashes,
    // so the type rows and search results float over the map as overlays.
    private var headerBar: some View {
        HStack(alignment: .center, spacing: 8) {
            if isSearching {
                searchField
            } else {
                visitFilterControl

                Spacer(minLength: 8)

                searchButton
                categoryFilterButton
            }
        }
        .controlSize(.small)
        .frame(height: 44)
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var searchButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.2)) {
                isSearching = true
                showingCategoryPicker = false
            }
            searchFocused = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Search places")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search your places", text: $searchText)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.regularMaterial, in: Capsule())

            Button("Cancel") {
                closeSearch()
            }
            .font(.ui(.subheadline, weight: .medium))
        }
    }

    private var visitFilterControl: some View {
        HStack(spacing: 6) {
            ForEach(MapVisitFilter.allCases) { filter in
                Group {
                    if visitFilter == filter {
                        Button(filter.rawValue) {
                            visitFilter = filter
                        }
                        .buttonStyle(.glassProminent)
                    } else {
                        Button(filter.rawValue) {
                            visitFilter = filter
                        }
                        .buttonStyle(.glass)
                    }
                }
                .accessibilityAddTraits(visitFilter == filter ? .isSelected : [])
            }
        }
        .font(.ui(.subheadline, weight: .medium))
        .buttonBorderShape(.capsule)
        .sensoryFeedback(.selection, trigger: visitFilter)
    }

    private var categoryFilterButton: some View {
        Group {
            if showingCategoryPicker {
                Button {
                    toggleCategoryPicker()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.glassProminent)
            } else {
                Button {
                    toggleCategoryPicker()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.body.weight(.semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.glass)
            }
        }
        .buttonBorderShape(.circle)
        .overlay(alignment: .topTrailing) {
            if selectedCategory != nil && !showingCategoryPicker {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 10, height: 10)
                    .overlay {
                        Circle().strokeBorder(.white, lineWidth: 1.5)
                    }
            }
        }
        .accessibilityLabel(selectedCategory.map { "Filter by type, \($0.rawValue) selected" } ?? "Filter by type")
    }

    private func categoryRow(title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.footnote.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.regularMaterial), in: Capsule())
                    .foregroundStyle(isSelected ? Color.white : Color.primary)

                Image(systemName: systemImage)
                    .font(.ui(.subheadline, weight: .medium))
                    .frame(width: 36, height: 36)
                    .background(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.regularMaterial), in: Circle())
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var countText: String {
        mappedIdeas.count == 1 ? "1 place shown" : "\(mappedIdeas.count) places shown"
    }

    // MARK: Search

    // Searches every saved place with a coordinate, ignoring the active filters.
    private var searchResults: [DateIdea] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        return Array(
            store.ideas
                .filter { idea in
                    idea.location.latitude != nil && idea.location.longitude != nil && (
                        idea.title.localizedCaseInsensitiveContains(query)
                        || idea.location.name.localizedCaseInsensitiveContains(query)
                        || idea.location.address.localizedCaseInsensitiveContains(query)
                    )
                }
                .prefix(6)
        )
    }

    @ViewBuilder
    private var searchResultsPanel: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !query.isEmpty {
            VStack(spacing: 0) {
                if searchResults.isEmpty {
                    Text("No saved places match \"\(query)\"")
                        .font(.ui(.footnote))
                        .foregroundStyle(.secondary)
                        .padding(14)
                } else {
                    ForEach(searchResults) { idea in
                        Button {
                            selectSearchResult(idea)
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(idea.hasBeenVisited(by: store.currentUserID) ? Theme.visited : Theme.endingSoon)
                                    .frame(width: 10, height: 10)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(idea.title)
                                        .font(.placeTitle(.subheadline))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Text(idea.location.address)
                                        .font(.ui(.caption))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if idea.id != searchResults.last?.id {
                            Divider()
                                .padding(.leading, 34)
                        }
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func selectSearchResult(_ idea: DateIdea) {
        // Clear any filter that would hide the picked place's pin.
        if !visitFilter.matches(idea, currentUserID: store.currentUserID) {
            visitFilter = .all
        }
        if let selectedCategory, selectedCategory != idea.category {
            self.selectedCategory = nil
        }

        withAnimation(.smooth(duration: 0.3)) {
            selectedIdeaID = idea.id
            if let coordinate = idea.mapCoordinate {
                position = .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            }
        }
        closeSearch()
    }

    private func closeSearch() {
        searchFocused = false
        withAnimation(.smooth(duration: 0.2)) {
            isSearching = false
            searchText = ""
        }
    }

    private func toggleCategoryPicker() {
        withAnimation(.smooth(duration: 0.25)) {
            showingCategoryPicker.toggle()
        }
    }

    private func selectCategory(_ category: IdeaCategory?) {
        withAnimation(.smooth(duration: 0.25)) {
            selectedCategory = category
            showingCategoryPicker = false
        }
    }

    private func dropSelectionIfHidden() {
        if let selectedIdeaID, !mappedIdeas.contains(where: { $0.id == selectedIdeaID }) {
            withAnimation(.smooth(duration: 0.2)) {
                self.selectedIdeaID = nil
            }
        }
    }

    private func distanceText(for idea: DateIdea) -> String? {
        guard let userLocation = store.userLocation,
              let latitude = idea.location.latitude,
              let longitude = idea.location.longitude else { return nil }

        let meters = userLocation.distance(from: CLLocation(latitude: latitude, longitude: longitude))
        return Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

enum MapVisitFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case wantToGo = "Want to go"
    case visited = "Visited"

    var id: String { rawValue }

    func matches(_ idea: DateIdea, currentUserID: String?) -> Bool {
        switch self {
        case .all:
            return true
        case .wantToGo:
            return !idea.hasBeenVisited(by: currentUserID)
        case .visited:
            return idea.hasBeenVisited(by: currentUserID)
        }
    }
}

struct MapPreviewCard: View {
    @EnvironmentObject private var store: DateIdeaStore
    let idea: DateIdea
    let distanceText: String?
    let onDismiss: () -> Void

    private var subtitle: String {
        [idea.category.rawValue, idea.location.address, distanceText]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var statusText: String {
        let base = isVisited ? "Visited" : "Want to go"
        let dealCount = idea.activeDeals.count
        guard dealCount > 0 else { return base }
        return "\(base) · \(dealCount) active deal\(dealCount == 1 ? "" : "s")"
    }

    private var isVisited: Bool {
        idea.hasBeenVisited(by: store.currentUserID)
    }

    var body: some View {
        NavigationLink(value: idea.id) {
            HStack(spacing: 12) {
                IdeaCoverImage(imageName: idea.imageName, url: idea.imageURL)
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(idea.title)
                        .font(.placeTitle(.subheadline))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.ui(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Label(statusText, systemImage: isVisited ? "checkmark.circle.fill" : "heart.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isVisited ? Theme.visited : Theme.endingSoon)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.ui(.footnote, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 2)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: Theme.cardShadow, radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss preview")
        }
    }
}

struct WorkbookMapPin: View {
    let isVisited: Bool
    var isSelected = false

    private var pinColor: Color {
        isVisited ? Theme.visited : Theme.endingSoon
    }

    private var outerSize: CGFloat { isSelected ? 46 : 38 }
    private var innerSize: CGFloat { isSelected ? 37 : 30 }

    var body: some View {
        ZStack {
            Circle()
                .fill(.background)
                .frame(width: outerSize, height: outerSize)
                .shadow(color: .black.opacity(isSelected ? 0.3 : 0.22), radius: isSelected ? 7 : 5, y: 3)

            Circle()
                .fill(pinColor)
                .frame(width: innerSize, height: innerSize)

            Image(systemName: isVisited ? "checkmark" : "heart.fill")
                .font(isSelected ? .subheadline.weight(.bold) : .caption.weight(.bold))
                .foregroundStyle(.white)
        }
        .accessibilityLabel(isVisited ? "Visited place" : "Want to go")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                            .font(.ui(.footnote))
                            .foregroundStyle(.red)
                    }
                }

                Section("Caption or comments") {
                    TextField("Paste the caption, top comment, address, deal text, or screenshot text", text: $importText, axis: .vertical)
                        .lineLimit(6...12)
                        .textInputAutocapitalization(.sentences)
                }
            }
            .themedScreenBackground()
            .navigationTitle("Import Link")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review") {
                        onImport()
                    }
                    .disabled(importURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                CaptionExtractorPrewarmer.prewarm()
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
