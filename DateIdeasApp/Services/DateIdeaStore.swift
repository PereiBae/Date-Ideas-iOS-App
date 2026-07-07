import CoreLocation
import Foundation
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

struct SaveConfirmation: Identifiable, Equatable {
    let id: UUID
    let ideaID: UUID
    let ideaTitle: String
}

enum IdeaSortOrder: String, CaseIterable, Identifiable {
    case dateAdded = "Date added"
    case alphabetical = "A to Z"
    case nearMe = "Near me"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dateAdded: "clock"
        case .alphabetical: "textformat"
        case .nearMe: "location"
        }
    }
}

struct IdeaFilter: Equatable {
    var category: IdeaCategory?
    var cuisineTag: CuisineTag?
    var foodTag: FoodTag?
    var visitedOnly = false
    var reviewMetric: ReviewMetric?
    var minimumReviewScore = 4.0

    var activeCount: Int {
        [category != nil, cuisineTag != nil, foodTag != nil, visitedOnly, reviewMetric != nil]
            .filter { $0 }
            .count
    }

    var isActive: Bool {
        activeCount > 0
    }

    func matches(_ idea: DateIdea) -> Bool {
        let categoryMatches = category.map { idea.category == $0 } ?? true
        let cuisineMatches = cuisineTag.map { idea.cuisineTags.contains($0) } ?? true
        let foodMatches = foodTag.map { idea.foodTags.contains($0) } ?? true
        let visitMatches = visitedOnly ? idea.hasVisited : true
        let reviewMatches = reviewMetric.map { metric in
            guard let review = idea.latestReview else { return false }
            return review.score(for: metric) >= minimumReviewScore
        } ?? true
        return categoryMatches && cuisineMatches && foodMatches && visitMatches && reviewMatches
    }
}

@MainActor
final class UserLocationProvider: NSObject, CLLocationManagerDelegate {
    var onUpdate: ((CLLocation?) -> Void)?
    var onDenied: (() -> Void)?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            onDenied?()
        default:
            manager.requestLocation()
        }
    }

    // Never prompts: fetches a fix only when permission was already granted.
    func requestLocationIfAuthorized() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch self.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.requestLocation()
            case .denied, .restricted:
                self.onDenied?()
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            self.onUpdate?(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.onUpdate?(nil)
        }
    }

    private var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }
}

@MainActor
final class DateIdeaStore: ObservableObject {
    @Published private(set) var ideas: [DateIdea]
    @Published var pendingDraft: ImportDraft?
    @Published private(set) var importStage: ImportStage?
    @Published var saveConfirmation: SaveConfirmation?
    private var importGeneration = 0
    @Published var filter = IdeaFilter()
    @Published var sortOrder: IdeaSortOrder = .dateAdded {
        didSet {
            if sortOrder == .nearMe {
                requestLocationForSorting()
            }
        }
    }
    @Published private(set) var userLocation: CLLocation?
    @Published private(set) var locationDenied = false
    private lazy var locationProvider = UserLocationProvider()

    private let storage: IdeaStorage
    private let extractor: PostExtractionServicing
    var remoteSaveHandler: ((DateIdea) async -> Void)?
    var remoteDeleteHandler: ((UUID) async -> Void)?

    init(storage: IdeaStorage = UserDefaultsIdeaStorage(), extractor: PostExtractionServicing = MockPostExtractionService()) {
        self.storage = storage
        self.extractor = extractor
        let storedIdeas = storage.loadIdeas()
        self.ideas = storedIdeas.isEmpty ? SampleData.ideas : storedIdeas
    }

    var filteredIdeas: [DateIdea] {
        sortedIdeas(ideas.filter(filter.matches))
    }

    func requestLocationForSorting() {
        locationDenied = false
        prepareLocationCallbacks()
        locationProvider.requestLocation()
    }

    func refreshUserLocationIfAuthorized() {
        prepareLocationCallbacks()
        locationProvider.requestLocationIfAuthorized()
    }

    private func prepareLocationCallbacks() {
        locationProvider.onUpdate = { [weak self] location in
            self?.userLocation = location
        }
        locationProvider.onDenied = { [weak self] in
            self?.locationDenied = true
        }
    }

    private func sortedIdeas(_ list: [DateIdea]) -> [DateIdea] {
        switch sortOrder {
        case .dateAdded:
            return list.sorted { $0.updatedAt > $1.updatedAt }
        case .alphabetical:
            return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .nearMe:
            guard let userLocation else {
                return list.sorted { $0.updatedAt > $1.updatedAt }
            }
            return list.sorted { distance(of: $0, from: userLocation) < distance(of: $1, from: userLocation) }
        }
    }

    // Ideas without coordinates sort to the end.
    private func distance(of idea: DateIdea, from location: CLLocation) -> Double {
        guard let latitude = idea.location.latitude, let longitude = idea.location.longitude else {
            return .greatestFiniteMagnitude
        }
        return location.distance(from: CLLocation(latitude: latitude, longitude: longitude))
    }

    var dealAlertIdeas: [DateIdea] {
        ideas
            .filter { !$0.endingSoonDeals.isEmpty || $0.activeDeals.contains(where: { $0.status == .needsConfirmation }) }
            .sorted { lhs, rhs in
                (lhs.activeDeals.compactMap(\.daysUntilEnd).min() ?? Int.max) < (rhs.activeDeals.compactMap(\.daysUntilEnd).min() ?? Int.max)
            }
    }

    var availableCuisineTags: [CuisineTag] {
        Array(Set(ideas.flatMap(\.cuisineTags))).sorted { $0.rawValue < $1.rawValue }
    }

    var availableFoodTags: [FoodTag] {
        Array(Set(ideas.flatMap(\.foodTags))).sorted { $0.rawValue < $1.rawValue }
    }

    func importLink(_ rawValue: String) async {
        await importLink(rawValue, supplementalText: "")
    }

    func importLink(_ rawValue: String, supplementalText: String) async {
        guard let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        await runImport(from: url, supplementalText: supplementalText)
    }

    func importQueuedShareIfNeeded() async {
        guard pendingDraft == nil, importStage == nil, let url = SharedImportQueue.dequeueFirst() else { return }
        await runImport(from: url, supplementalText: "")
    }

    func cancelImport() {
        importGeneration += 1
        importStage = nil
        pendingDraft = nil
    }

    private func runImport(from url: URL, supplementalText: String) async {
        importGeneration += 1
        let generation = importGeneration
        importStage = .fetchingCaption

        let draft = await extractor.extract(from: url, supplementalText: supplementalText) { [weak self] stage in
            guard let self, generation == self.importGeneration, self.importStage != nil else { return }
            self.importStage = stage
        }

        // The user may have dismissed the extraction sheet mid-flight.
        guard generation == importGeneration, importStage != nil else { return }
        importStage = nil
        pendingDraft = draft
    }

    func saveDraft(_ draft: ImportDraft) {
        let savedIdea = saveIdea(draft.extractedIdea)
        pendingDraft = nil
        saveConfirmation = SaveConfirmation(id: UUID(), ideaID: savedIdea.id, ideaTitle: savedIdea.title)
    }

    @discardableResult
    func saveIdea(_ idea: DateIdea) -> DateIdea {
        var nextIdea = idea
        nextIdea.updatedAt = .now
        var savedIdea = nextIdea

        if let duplicateIndex = ideas.firstIndex(where: { $0.duplicateKey == nextIdea.duplicateKey }) {
            var existing = ideas[duplicateIndex]
            existing.updatedAt = .now
            existing.deals.append(contentsOf: nextIdea.deals)
            existing.sourcePosts.append(contentsOf: nextIdea.sourcePosts)
            existing.tags = Array(Set(existing.tags + nextIdea.tags)).sorted { $0.rawValue < $1.rawValue }
            existing.cuisineTags = Array(Set(existing.cuisineTags + nextIdea.cuisineTags)).sorted { $0.rawValue < $1.rawValue }
            existing.foodTags = Array(Set(existing.foodTags + nextIdea.foodTags)).sorted { $0.rawValue < $1.rawValue }

            if existing.notes.isEmpty {
                existing.notes = nextIdea.notes
            }

            if existing.imageURL == nil {
                existing.imageURL = nextIdea.imageURL
            }

            if existing.imageName == nil {
                existing.imageName = nextIdea.imageName
            }

            ideas[duplicateIndex] = existing
            savedIdea = existing
        } else {
            ideas.insert(nextIdea, at: 0)
        }

        persist()
        syncIdeaIfNeeded(savedIdea)
        return savedIdea
    }

    func updateIdea(_ idea: DateIdea) {
        guard let index = ideas.firstIndex(where: { $0.id == idea.id }) else { return }
        var nextIdea = idea
        nextIdea.updatedAt = .now
        ideas[index] = nextIdea
        persist()
        syncIdeaIfNeeded(nextIdea)
    }

    func deleteIdea(_ idea: DateIdea) {
        deleteIdea(id: idea.id)
    }

    func deleteIdea(id: UUID) {
        ideas.removeAll { $0.id == id }
        persist()
        syncDeleteIfNeeded(id)
    }

    func deleteIdeas(at offsets: IndexSet, from visibleIdeas: [DateIdea]) {
        let idsToDelete = Set(offsets.compactMap { visibleIdeas[safe: $0]?.id })
        guard !idsToDelete.isEmpty else { return }
        ideas.removeAll { idsToDelete.contains($0.id) }
        persist()
        idsToDelete.forEach(syncDeleteIfNeeded)
    }

    func addVisit(_ visit: Visit, to idea: DateIdea) {
        guard let index = ideas.firstIndex(where: { $0.id == idea.id }) else { return }
        ideas[index].visits.insert(visit, at: 0)
        ideas[index].updatedAt = .now
        persist()
        syncIdeaIfNeeded(ideas[index])
    }

    func updateVisit(_ visit: Visit, in idea: DateIdea) {
        guard let ideaIndex = ideas.firstIndex(where: { $0.id == idea.id }),
              let visitIndex = ideas[ideaIndex].visits.firstIndex(where: { $0.id == visit.id }) else { return }
        ideas[ideaIndex].visits[visitIndex] = visit
        ideas[ideaIndex].visits.sort { $0.visitedAt > $1.visitedAt }
        ideas[ideaIndex].updatedAt = .now
        persist()
        syncIdeaIfNeeded(ideas[ideaIndex])
    }

    func deleteVisits(at offsets: IndexSet, from idea: DateIdea) {
        guard let index = ideas.firstIndex(where: { $0.id == idea.id }) else { return }
        ideas[index].visits.remove(atOffsets: offsets)
        ideas[index].updatedAt = .now
        persist()
        syncIdeaIfNeeded(ideas[index])
    }

    func expireDeal(_ deal: Deal, in idea: DateIdea) {
        guard let ideaIndex = ideas.firstIndex(where: { $0.id == idea.id }),
              let dealIndex = ideas[ideaIndex].deals.firstIndex(where: { $0.id == deal.id }) else { return }
        ideas[ideaIndex].deals[dealIndex].status = .expired
        ideas[ideaIndex].updatedAt = .now
        persist()
        syncIdeaIfNeeded(ideas[ideaIndex])
    }

    func replaceIdeasFromRemote(_ remoteIdeas: [DateIdea]) {
        ideas = remoteIdeas.sorted { $0.updatedAt > $1.updatedAt }
    }

    func clearIdeasForRemoteLoad() {
        ideas = []
    }

    func restoreLocalIdeas() {
        let storedIdeas = storage.loadIdeas()
        ideas = storedIdeas.isEmpty ? SampleData.ideas : storedIdeas
    }

    private func persist() {
        storage.saveIdeas(ideas)
    }

    private func syncIdeaIfNeeded(_ idea: DateIdea) {
        guard let remoteSaveHandler else { return }
        Task {
            await remoteSaveHandler(idea)
        }
    }

    private func syncDeleteIfNeeded(_ id: UUID) {
        guard let remoteDeleteHandler else { return }
        Task {
            await remoteDeleteHandler(id)
        }
    }
}

struct AppUser: Identifiable, Codable, Hashable {
    var id: String
    var displayName: String
    var email: String?
    var photoURL: URL?

    var initials: String {
        let parts = displayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first)
        if letters.isEmpty {
            return email?.prefix(1).uppercased() ?? "?"
        }
        return String(letters).uppercased()
    }
}

struct Workbook: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var ownerID: String
    var memberIDs: [String]
    var inviteCode: String
    var isPersonal: Bool
    var createdAt: Date
    var updatedAt: Date

    var isShareable: Bool {
        !isPersonal
    }
}

enum CollaborationError: LocalizedError {
    case firebaseUnavailable
    case firebaseNotConfigured
    case missingUser
    case missingWorkbook
    case workbookNotFound
    case invalidSnapshot

    var errorDescription: String? {
        switch self {
        case .firebaseUnavailable:
            "Firebase SDK is not linked yet."
        case .firebaseNotConfigured:
            "Firebase is not configured. Add GoogleService-Info.plist to the app target."
        case .missingUser:
            "Sign in before using shared workbooks."
        case .missingWorkbook:
            "Select a workbook first."
        case .workbookNotFound:
            "No workbook matched that invite code."
        case .invalidSnapshot:
            "The shared workbook data could not be read."
        }
    }
}

@MainActor
final class CollaborationStore: ObservableObject {
    @Published private(set) var currentUser: AppUser?
    @Published private(set) var workbooks: [Workbook] = []
    @Published private(set) var activeWorkbook: Workbook?
    @Published private(set) var isSyncing = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private weak var dateIdeaStore: DateIdeaStore?

#if canImport(FirebaseFirestore)
    private var workbooksListener: ListenerRegistration?
    private var ideasListener: ListenerRegistration?
#endif

    var isFirebaseSDKLinked: Bool {
#if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        true
#else
        false
#endif
    }

    var isFirebaseConfigured: Bool {
#if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        FirebaseApp.app() != nil
#else
        false
#endif
    }

    var canUseFirebase: Bool {
        isFirebaseSDKLinked && isFirebaseConfigured
    }

    func attach(dateIdeaStore: DateIdeaStore) {
        self.dateIdeaStore = dateIdeaStore
        dateIdeaStore.remoteSaveHandler = { [weak self] idea in
            await self?.saveIdeaToActiveWorkbook(idea)
        }
        dateIdeaStore.remoteDeleteHandler = { [weak self] id in
            await self?.deleteIdeaFromActiveWorkbook(id)
        }
        start()
    }

    func start() {
        errorMessage = nil
#if canImport(FirebaseAuth) && canImport(FirebaseFirestore) && canImport(FirebaseCore)
        guard isFirebaseConfigured else {
            statusMessage = isFirebaseSDKLinked ? "Firebase SDK linked. Add GoogleService-Info.plist to enable sign in." : "Firebase setup required."
            return
        }

        if let user = Auth.auth().currentUser {
            let appUser = AppUser(
                id: user.uid,
                displayName: user.displayName ?? user.email ?? "Date Planner",
                email: user.email,
                photoURL: user.photoURL
            )
            currentUser = appUser
            dateIdeaStore?.clearIdeasForRemoteLoad()
            observeWorkbooks(for: appUser.id)
            Task {
                await performFirebaseAction("Could not load personal workbook.") {
                    try await ensurePersonalWorkbook(for: appUser)
                }
            }
            statusMessage = "Loading your workbooks."
        } else {
            currentUser = nil
            workbooks = []
            activeWorkbook = nil
            statusMessage = "Sign in to use shared workbooks."
        }
#else
        statusMessage = "Firebase setup required."
#endif
    }

    func signIn(email: String, password: String) async {
        await performFirebaseAction("Could not sign in.") {
#if canImport(FirebaseAuth) && canImport(FirebaseFirestore) && canImport(FirebaseCore)
            guard self.isFirebaseConfigured else { throw CollaborationError.firebaseNotConfigured }
            let result = try await Self.signInWithFirebase(email: email, password: password)
            let user = AppUser(
                id: result.user.uid,
                displayName: result.user.displayName ?? result.user.email ?? "Date Planner",
                email: result.user.email,
                photoURL: result.user.photoURL
            )
            try await self.finishSignIn(user: user, status: "Signed in.")
#else
            throw CollaborationError.firebaseUnavailable
#endif
        }
    }

    func createAccount(email: String, password: String, displayName: String) async {
        await performFirebaseAction("Could not create account.") {
#if canImport(FirebaseAuth) && canImport(FirebaseFirestore) && canImport(FirebaseCore)
            guard self.isFirebaseConfigured else { throw CollaborationError.firebaseNotConfigured }
            let result = try await Self.createFirebaseUser(email: email, password: password)
            let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let user = AppUser(
                id: result.user.uid,
                displayName: trimmedName.isEmpty ? email : trimmedName,
                email: result.user.email,
                photoURL: result.user.photoURL
            )
            try await self.finishSignIn(user: user, status: "Account created.")
#else
            throw CollaborationError.firebaseUnavailable
#endif
        }
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async {
        await performFirebaseAction("Could not sign in with Apple.") {
#if canImport(FirebaseAuth) && canImport(FirebaseFirestore) && canImport(FirebaseCore)
            guard self.isFirebaseConfigured else { throw CollaborationError.firebaseNotConfigured }
            let result = try await Self.signInWithAppleFirebase(idToken: idToken, rawNonce: rawNonce, fullName: fullName)
            let formattedName = fullName.map { PersonNameComponentsFormatter().string(from: $0) }
            let fallbackName = formattedName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let user = AppUser(
                id: result.user.uid,
                displayName: result.user.displayName ?? fallbackName?.nilIfEmpty ?? result.user.email ?? "Apple User",
                email: result.user.email,
                photoURL: result.user.photoURL
            )
            try await self.finishSignIn(user: user, status: "Signed in with Apple.")
#else
            throw CollaborationError.firebaseUnavailable
#endif
        }
    }

    func signOut() async {
        await performFirebaseAction("Could not sign out.") {
#if canImport(FirebaseAuth) && canImport(FirebaseFirestore) && canImport(FirebaseCore)
            try Auth.auth().signOut()
            self.workbooksListener?.remove()
            self.ideasListener?.remove()
            self.currentUser = nil
            self.workbooks = []
            self.activeWorkbook = nil
            self.dateIdeaStore?.restoreLocalIdeas()
            self.statusMessage = "Signed out."
#else
            throw CollaborationError.firebaseUnavailable
#endif
        }
    }

    func createWorkbook(named name: String) async {
        await performFirebaseAction("Could not create workbook.") {
#if canImport(FirebaseFirestore) && canImport(FirebaseAuth) && canImport(FirebaseCore)
            guard self.isFirebaseConfigured else { throw CollaborationError.firebaseNotConfigured }
            guard let user = self.currentUser else { throw CollaborationError.missingUser }

            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let workbookRef = Firestore.firestore().collection("workbooks").document()
            let workbook = Workbook(
                id: workbookRef.documentID,
                name: trimmedName.isEmpty ? "Our Dates" : trimmedName,
                ownerID: user.id,
                memberIDs: [user.id],
                inviteCode: Self.makeInviteCode(),
                isPersonal: false,
                createdAt: .now,
                updatedAt: .now
            )

            try await Self.setData(Self.dictionary(from: workbook), at: workbookRef)
            self.activeWorkbook = workbook
            self.observeIdeas(in: workbook)
            self.statusMessage = "Workbook created."
#else
            throw CollaborationError.firebaseUnavailable
#endif
        }
    }

    func joinWorkbook(inviteCode: String) async {
        await performFirebaseAction("Could not join workbook.") {
#if canImport(FirebaseFirestore) && canImport(FirebaseAuth) && canImport(FirebaseCore)
            guard self.isFirebaseConfigured else { throw CollaborationError.firebaseNotConfigured }
            guard let user = self.currentUser else { throw CollaborationError.missingUser }

            let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let snapshot = try await Self.getDocuments(
                Firestore.firestore()
                    .collection("workbooks")
                    .whereField("inviteCode", isEqualTo: code)
                    .limit(to: 1)
            )

            guard let document = snapshot.documents.first else { throw CollaborationError.workbookNotFound }
            try await Self.updateData(
                [
                    "memberIDs": FieldValue.arrayUnion([user.id]),
                    "updatedAt": Timestamp(date: .now)
                ],
                at: document.reference
            )

            if let workbook = Self.workbook(from: document.documentID, data: document.data()) {
                self.activeWorkbook = workbook
                self.observeIdeas(in: workbook)
            }
            self.statusMessage = "Joined workbook."
#else
            throw CollaborationError.firebaseUnavailable
#endif
        }
    }

    func selectWorkbook(_ workbook: Workbook?) {
        activeWorkbook = workbook
        if let workbook {
            observeIdeas(in: workbook)
            statusMessage = "Viewing \(workbook.name)."
        } else {
            stopIdeasListener()
            dateIdeaStore?.clearIdeasForRemoteLoad()
            statusMessage = currentUser == nil ? "Viewing your local workbook." : "Select a workbook."
        }
    }

    func saveIdeaToActiveWorkbook(_ idea: DateIdea) async {
        guard canUseFirebase, let workbook = activeWorkbook else { return }
        await performFirebaseAction("Could not sync place.") {
#if canImport(FirebaseFirestore) && canImport(FirebaseAuth) && canImport(FirebaseCore)
            var nextIdea = idea
            if nextIdea.createdByUserID == nil, let user = self.currentUser {
                nextIdea.createdByUserID = user.id
                nextIdea.createdByDisplayName = user.displayName
                nextIdea.createdByPhotoURL = user.photoURL
            }

            let document = Firestore.firestore()
                .collection("workbooks")
                .document(workbook.id)
                .collection("ideas")
                .document(nextIdea.id.uuidString)
            try await Self.setData(Self.dictionary(from: nextIdea), at: document)
#else
            throw CollaborationError.firebaseUnavailable
#endif
        }
    }

    func deleteIdeaFromActiveWorkbook(_ id: UUID) async {
        guard canUseFirebase, let workbook = activeWorkbook else { return }
        await performFirebaseAction("Could not delete shared place.") {
#if canImport(FirebaseFirestore) && canImport(FirebaseAuth) && canImport(FirebaseCore)
            let document = Firestore.firestore()
                .collection("workbooks")
                .document(workbook.id)
                .collection("ideas")
                .document(id.uuidString)
            try await Self.deleteDocument(document)
#else
            throw CollaborationError.firebaseUnavailable
#endif
        }
    }

    private func performFirebaseAction(_ failurePrefix: String, action: () async throws -> Void) async {
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        do {
            try await action()
        } catch {
            errorMessage = "\(failurePrefix) \(error.localizedDescription)"
        }
    }

    private func finishSignIn(user: AppUser, status: String) async throws {
#if canImport(FirebaseFirestore) && canImport(FirebaseAuth) && canImport(FirebaseCore)
        currentUser = user
        activeWorkbook = nil
        workbooks = []
        dateIdeaStore?.clearIdeasForRemoteLoad()
        try await upsertUser(user)
        observeWorkbooks(for: user.id)
        try await ensurePersonalWorkbook(for: user)
        statusMessage = status
#else
        throw CollaborationError.firebaseUnavailable
#endif
    }

    private func observeWorkbooks(for userID: String) {
#if canImport(FirebaseFirestore) && canImport(FirebaseAuth) && canImport(FirebaseCore)
        guard isFirebaseConfigured else { return }
        workbooksListener?.remove()
        workbooksListener = Firestore.firestore()
            .collection("workbooks")
            .whereField("memberIDs", arrayContains: userID)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = "Could not load workbooks. \(error.localizedDescription)"
                        return
                    }

                    let nextWorkbooks = snapshot?.documents.compactMap { document in
                        Self.workbook(from: document.documentID, data: document.data())
                    }
                    .sorted(by: Self.workbookSort) ?? []

                    self.workbooks = nextWorkbooks

                    if nextWorkbooks.isEmpty, let user = self.currentUser {
                        Task {
                            await self.performFirebaseAction("Could not create personal workbook.") {
                                try await self.ensurePersonalWorkbook(for: user)
                            }
                        }
                        return
                    }

                    if let active = self.activeWorkbook,
                       let refreshed = nextWorkbooks.first(where: { $0.id == active.id }) {
                        self.activeWorkbook = refreshed
                    } else if self.activeWorkbook == nil {
                        let first = nextWorkbooks.first(where: \.isPersonal) ?? nextWorkbooks.first
                        if let first {
                            self.activeWorkbook = first
                            self.observeIdeas(in: first)
                        }
                    }
                }
            }
#endif
    }

    private func ensurePersonalWorkbook(for user: AppUser) async throws {
#if canImport(FirebaseFirestore) && canImport(FirebaseAuth) && canImport(FirebaseCore)
        guard isFirebaseConfigured else { throw CollaborationError.firebaseNotConfigured }

        if let personal = workbooks.first(where: \.isPersonal) {
            if activeWorkbook == nil {
                activeWorkbook = personal
                observeIdeas(in: personal)
            }
            return
        }

        let existingPersonal = try await Self.getDocuments(
            Firestore.firestore()
                .collection("workbooks")
                .whereField("ownerID", isEqualTo: user.id)
        )

        if let document = existingPersonal.documents.first(where: { ($0.data()["isPersonal"] as? Bool) == true }),
           let personal = Self.workbook(from: document.documentID, data: document.data()) {
            activeWorkbook = personal
            observeIdeas(in: personal)
            return
        }

        let personalID = "personal_\(user.id)"
        let document = Firestore.firestore().collection("workbooks").document(personalID)
        let personal = Workbook(
            id: personalID,
            name: "Personal workbook",
            ownerID: user.id,
            memberIDs: [user.id],
            inviteCode: Self.makeInviteCode(),
            isPersonal: true,
            createdAt: .now,
            updatedAt: .now
        )
        try await Self.setData(Self.dictionary(from: personal), at: document)
        activeWorkbook = personal
        observeIdeas(in: personal)
#else
        throw CollaborationError.firebaseUnavailable
#endif
    }

    private func observeIdeas(in workbook: Workbook) {
#if canImport(FirebaseFirestore) && canImport(FirebaseAuth) && canImport(FirebaseCore)
        guard isFirebaseConfigured else { return }
        ideasListener?.remove()
        ideasListener = Firestore.firestore()
            .collection("workbooks")
            .document(workbook.id)
            .collection("ideas")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = "Could not load shared places. \(error.localizedDescription)"
                        return
                    }

                    let remoteIdeas = snapshot?.documents.compactMap { document in
                        Self.dateIdea(from: document.data())
                    } ?? []
                    self.dateIdeaStore?.replaceIdeasFromRemote(remoteIdeas)
                }
            }
#endif
    }

    private func stopIdeasListener() {
#if canImport(FirebaseFirestore)
        ideasListener?.remove()
        ideasListener = nil
#endif
    }

    private func upsertUser(_ user: AppUser) async throws {
#if canImport(FirebaseFirestore) && canImport(FirebaseAuth) && canImport(FirebaseCore)
        let document = Firestore.firestore().collection("users").document(user.id)
        try await Self.setData(Self.dictionary(from: user), at: document)
#else
        throw CollaborationError.firebaseUnavailable
#endif
    }

    private static func makeInviteCode() -> String {
        String(UUID().uuidString.prefix(8)).uppercased()
    }

    private static func workbookSort(_ lhs: Workbook, _ rhs: Workbook) -> Bool {
        if lhs.isPersonal != rhs.isPersonal {
            return lhs.isPersonal
        }
        return lhs.updatedAt > rhs.updatedAt
    }
}

#if canImport(FirebaseAuth)
private extension CollaborationStore {
    static func signInWithFirebase(email: String, password: String) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { continuation in
            Auth.auth().signIn(withEmail: email, password: password) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: CollaborationError.invalidSnapshot)
                }
            }
        }
    }

    static func createFirebaseUser(email: String, password: String) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { continuation in
            Auth.auth().createUser(withEmail: email, password: password) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: CollaborationError.invalidSnapshot)
                }
            }
        }
    }

    static func signInWithAppleFirebase(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> AuthDataResult {
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: rawNonce,
            fullName: fullName
        )

        return try await withCheckedThrowingContinuation { continuation in
            Auth.auth().signIn(with: credential) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: CollaborationError.invalidSnapshot)
                }
            }
        }
    }
}
#endif

#if canImport(FirebaseFirestore)
private extension CollaborationStore {
    static func setData(_ data: [String: Any], at document: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.setData(data, merge: true) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    static func updateData(_ data: [AnyHashable: Any], at document: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.updateData(data) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    static func deleteDocument(_ document: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    static func getDocuments(_ query: Query) async throws -> QuerySnapshot {
        try await withCheckedThrowingContinuation { continuation in
            query.getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: CollaborationError.invalidSnapshot)
                }
            }
        }
    }

    static func dictionary(from workbook: Workbook) -> [String: Any] {
        [
            "name": workbook.name,
            "ownerID": workbook.ownerID,
            "memberIDs": workbook.memberIDs,
            "inviteCode": workbook.inviteCode,
            "isPersonal": workbook.isPersonal,
            "createdAt": Timestamp(date: workbook.createdAt),
            "updatedAt": Timestamp(date: workbook.updatedAt)
        ]
    }

    static func dictionary(from user: AppUser) -> [String: Any] {
        [
            "displayName": user.displayName,
            "email": user.email as Any,
            "photoURL": user.photoURL?.absoluteString as Any
        ]
    }

    static func dictionary(from idea: DateIdea) -> [String: Any] {
        guard let data = try? JSONEncoder.dateIdeas.encode(idea),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    static func workbook(from id: String, data: [String: Any]) -> Workbook? {
        guard let name = data["name"] as? String,
              let ownerID = data["ownerID"] as? String,
              let memberIDs = data["memberIDs"] as? [String],
              let inviteCode = data["inviteCode"] as? String else {
            return nil
        }

        return Workbook(
            id: id,
            name: name,
            ownerID: ownerID,
            memberIDs: memberIDs,
            inviteCode: inviteCode,
            isPersonal: data["isPersonal"] as? Bool ?? false,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .now,
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? .now
        )
    }

    static func dateIdea(from data: [String: Any]) -> DateIdea? {
        guard JSONSerialization.isValidJSONObject(data),
              let json = try? JSONSerialization.data(withJSONObject: data) else {
            return nil
        }
        return try? JSONDecoder.dateIdeas.decode(DateIdea.self, from: json)
    }
}
#endif

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
